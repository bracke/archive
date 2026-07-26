with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Files;
with Tarlib.Outputs;
with Tarlib.Writers;
with Zlib;

with Archive.Archives.Entries;
with Archive.Archives.Index;
with Archive.Archives.Readers.Tar;
with Archive.Types;

package body Archive.Writes.Tar is
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Integrity_State;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Writes.Plans.Entry_Decision;
   use type Archive.Writes.Plans.Plan_Status;
   use type Archive.Writes.Plans.Write_Action;
   use type Archive.Types.Entry_Id;
   use type Archive.Types.Uncompressed_Size;
   use type Tarlib.Errors.Status_Code;

   function Map_Error
     (Status : Tarlib.Errors.Status)
      return Archive.Archives.Errors.Error_Code
   is
   begin
      case Status.Code is
         when Tarlib.Errors.Success =>
            return Archive.Archives.Errors.Ok;
         when Tarlib.Errors.Output_Failure =>
            return Archive.Archives.Errors.Write_Failed;
         when Tarlib.Errors.Invalid_Path | Tarlib.Errors.Path_Too_Long
            | Tarlib.Errors.Invalid_Entry_Kind | Tarlib.Errors.Invalid_Metadata
            | Tarlib.Errors.Invalid_Size =>
            return Archive.Archives.Errors.Invalid_Format;
         when others =>
            return Archive.Archives.Errors.Unsupported_Method;
      end case;
   end Map_Error;

   function Build_Stream
     (Plan : Archive.Writes.Plans.Write_Plan;
      Sink : in out Tarlib.Outputs.Output_Sink'Class;
      Source_Path : String)
      return Archive.Archives.Errors.Error_Code
   is
      Writer : Tarlib.Writers.Writer;
      Status : Tarlib.Errors.Status;

      function Source_Change_For
        (Id : Archive.Types.Entry_Id)
         return Natural
      is
         Position : Natural := 0;
      begin
         for Change of Plan.Changes loop
            Position := Position + 1;
            if Change.Request.Source_Entry = Id
              and then Change.Request.Action in Archive.Writes.Plans.Replace_File
                | Archive.Writes.Plans.Remove_Entry
                | Archive.Writes.Plans.Rename_Entry
            then
               return Position;
            end if;
         end loop;
         return 0;
      end Source_Change_For;

      function Has_Source_Mutations return Boolean is
      begin
         for Change of Plan.Changes loop
            if Change.Request.Action in Archive.Writes.Plans.Replace_File
              | Archive.Writes.Plans.Remove_Entry
              | Archive.Writes.Plans.Rename_Entry
            then
               return True;
            end if;
         end loop;
         return False;
      end Has_Source_Mutations;

      function Metadata_Value (Text : String; Key : String) return String is
         Prefix : constant String := Key & "=";
         Start  : constant Natural := Ada.Strings.Fixed.Index (Text, Prefix);
         Stop   : Natural;
      begin
         if Start = 0 then
            return "";
         end if;

         Stop := Ada.Strings.Fixed.Index (Text (Start + Prefix'Length .. Text'Last), ";");
         if Stop = 0 then
            return Text (Start + Prefix'Length .. Text'Last);
         end if;
         return Text (Start + Prefix'Length .. Stop - 1);
      end Metadata_Value;

      function Device_For
        (Item : Archive.Archives.Entries.Archive_Entry)
         return Tarlib.Entries.Device_Numbers
      is
         Meta  : constant String := To_String (Item.Format_Metadata);
         Major : constant String := Metadata_Value (Meta, "tar.device_major");
         Minor : constant String := Metadata_Value (Meta, "tar.device_minor");
      begin
         if Major = "" or else Minor = "" then
            return Tarlib.Entries.No_Device;
         end if;

         return
           (Major => Tarlib.Entries.Device_Number'Value (Major),
            Minor => Tarlib.Entries.Device_Number'Value (Minor));
      exception
         when others =>
            return Tarlib.Entries.No_Device;
      end Device_For;

      procedure Add_Bytes
        (Name  : String;
         Bytes : Zlib.Byte_Array)
      is
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
      begin
         for Index in Bytes'Range loop
            Data (Ada.Streams.Stream_Element_Offset (Index - Bytes'First + 1)) :=
              Ada.Streams.Stream_Element (Bytes (Index));
         end loop;

         Tarlib.Writers.Begin_File
           (Writer, Name, Tarlib.Byte_Count (Bytes'Length), Status);
         if Status.Code /= Tarlib.Errors.Success then
            return;
         end if;

         Tarlib.Writers.Write (Writer, Data, Status);
         if Status.Code /= Tarlib.Errors.Success then
            return;
         end if;

         Tarlib.Writers.End_Entry (Writer, Status);
      end Add_Bytes;

      procedure Add_Streamed
        (Name : String;
         Item : Archive.Archives.Entries.Archive_Entry)
      is
         Written : Archive.Types.Uncompressed_Size := 0;

         procedure Consume
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean)
         is
            Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
         begin
            Continue := Status.Code = Tarlib.Errors.Success;
            if not Continue then
               return;
            end if;

            for Index in Bytes'Range loop
               Data (Ada.Streams.Stream_Element_Offset (Index - Bytes'First + 1)) :=
                 Ada.Streams.Stream_Element (Bytes (Index));
            end loop;

            Tarlib.Writers.Write (Writer, Data, Status);
            if Status.Code = Tarlib.Errors.Success then
               Written := Written + Archive.Types.Uncompressed_Size (Bytes'Length);
            else
               Continue := False;
            end if;
         end Consume;
      begin
         if not Item.Uncompressed.Present then
            Status := (Code => Tarlib.Errors.Input_Failure);
            return;
         end if;

         Tarlib.Writers.Begin_File
           (Writer, Name, Tarlib.Byte_Count (Item.Uncompressed.Value), Status);
         if Status.Code /= Tarlib.Errors.Success then
            return;
         end if;

         declare
            Payload : constant Archive.Archives.Readers.Tar.Stream_Result :=
              Archive.Archives.Readers.Tar.Stream_Payload_File
                (Source_Path, Item, Consume'Access);
         begin
            if Payload.Status /= Archive.Archives.Errors.Ok
              or else Payload.Integrity = Archive.Archives.Entries.Failed
              or else Payload.Bytes_Written /= Item.Uncompressed.Value
              or else Written /= Item.Uncompressed.Value
            then
               Status := (Code => Tarlib.Errors.Input_Failure);
               return;
            end if;
         end;

         Tarlib.Writers.End_Entry (Writer, Status);
      end Add_Streamed;

      procedure Add_Existing
        (Item : Archive.Archives.Entries.Archive_Entry;
         Name : String)
      is
      begin
         case Item.Kind is
            when Archive.Archives.Entries.Regular_File =>
               Add_Streamed (Name, Item);

            when Archive.Archives.Entries.Directory =>
               Tarlib.Writers.Add_Directory (Writer, Name, Status);

            when Archive.Archives.Entries.Symbolic_Link =>
               Tarlib.Writers.Add_Symbolic_Link
                 (Writer, Name, To_String (Item.Link_Target), Status);

            when Archive.Archives.Entries.Hard_Link =>
               Tarlib.Writers.Add_Hard_Link
                 (Writer, Name, To_String (Item.Link_Target), Status);

            when Archive.Archives.Entries.Character_Device =>
               Tarlib.Writers.Add_Character_Device
                 (Writer, Name, Device_For (Item), Status);

            when Archive.Archives.Entries.Block_Device =>
               Tarlib.Writers.Add_Block_Device
                 (Writer, Name, Device_For (Item), Status);

            when Archive.Archives.Entries.FIFO =>
               Tarlib.Writers.Add_FIFO (Writer, Name, Status);

            when others =>
               Status := (Code => Tarlib.Errors.Invalid_Entry_Kind);
         end case;
      end Add_Existing;
   begin
      if Plan.Status /= Archive.Writes.Plans.Write_Plan_Ready then
         return Archive.Archives.Errors.Unsupported_Method;
      elsif Has_Source_Mutations and then Source_Path = "" then
         return Archive.Archives.Errors.Unsupported_Method;
      end if;

      Tarlib.Writers.Initialize (Writer, Sink, Status);
      if Status.Code /= Tarlib.Errors.Success then
         return Map_Error (Status);
      end if;

      if Source_Path /= "" then
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
            declare
               Id       : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item     : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Plan.Index, Id);
               Position : constant Natural := Source_Change_For (Id);
            begin
               if not Item.Synthetic then
                  if Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Remove_Entry
                  then
                     null;
                  elsif Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Replace_File
                  then
                     Tarlib.Files.Add_File
                       (Writer,
                        To_String (Plan.Changes.Element (Position).Request.Host_Source),
                        To_String (Plan.Changes.Element (Position).Request.Target_Path),
                        Status);
                  elsif Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Rename_Entry
                  then
                     Add_Existing
                       (Item, To_String (Plan.Changes.Element (Position).Request.Replacement_Path));
                  else
                     Add_Existing (Item, To_String (Item.Original_Path));
                  end if;

                  if Status.Code /= Tarlib.Errors.Success then
                     return Map_Error (Status);
                  end if;
               end if;
            end;
         end loop;
      end if;

      for Change of Plan.Changes loop
         if Change.Decision /= Archive.Writes.Plans.Entry_Ready then
            return Archive.Archives.Errors.Invalid_Format;
         end if;

         case Change.Request.Action is
            when Archive.Writes.Plans.Add_File =>
               Tarlib.Files.Add_File
                 (Writer,
                  To_String (Change.Request.Host_Source),
                  To_String (Change.Request.Target_Path),
                  Status);
            when Archive.Writes.Plans.Add_Directory =>
               Tarlib.Files.Add_Tree
                 (Writer,
                  To_String (Change.Request.Host_Source),
                  To_String (Change.Request.Target_Path),
                  Status);
            when Archive.Writes.Plans.Replace_File | Archive.Writes.Plans.Remove_Entry
               | Archive.Writes.Plans.Rename_Entry =>
               null;
         end case;

         if Status.Code /= Tarlib.Errors.Success then
            return Map_Error (Status);
         end if;
      end loop;

      Tarlib.Writers.Finish (Writer, Status);
      return Map_Error (Status);
   end Build_Stream;

   function Build_Stream
     (Plan : Archive.Writes.Plans.Write_Plan;
      Sink : in out Tarlib.Outputs.Output_Sink'Class)
      return Archive.Archives.Errors.Error_Code
   is
   begin
      return Build_Stream (Plan, Sink, Source_Path => "");
   end Build_Stream;
end Archive.Writes.Tar;
