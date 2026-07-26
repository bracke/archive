with Ada.Directories;
with Ada.Numerics.Discrete_Random;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;

with Archive.Archives.Readers.Dispatch;
with Archive.Compression.Zlib;
with Archive.Resource_Limits;
with Archive.Temporary_Resources;
with Archive.Types;
with Archive.Writes.Tar;
with Archive.Writes.Zip;
with Tarlib.Errors;
with Tarlib.Outputs;
with Zlib;
package body Archive.Writes.Execution is
   use type Archive.Writes.Plans.Plan_Status;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Archives.Formats.Format_Id;
   use type Archive.Writes.Plans.Entry_Decision;
   use type Archive.Writes.Results.Write_Status;
   use type Archive.Writes.Plans.Write_Action;
   use type Ada.Streams.Stream_Element_Offset;

   Chunk_Size : constant Ada.Streams.Stream_Element_Count := 32_768;
   subtype Temp_Nonce is Natural range 0 .. 16#7FFF_FFFF#;
   package Temp_Nonce_Random is new Ada.Numerics.Discrete_Random (Temp_Nonce);
   Temp_Generator : Temp_Nonce_Random.Generator;

   type File_Zip_Sink is limited new Archive.Writes.Zip.Output_Sink with record
      File : Ada.Streams.Stream_IO.File_Type;
   end record;

   type File_Tar_Sink is limited new Tarlib.Outputs.Output_Sink with record
      File : Ada.Streams.Stream_IO.File_Type;
   end record;

   type File_Tar_Gzip_Sink is limited new Tarlib.Outputs.Output_Sink with record
      File   : Ada.Streams.Stream_IO.File_Type;
      Stream : Archive.Compression.Zlib.Deflate_Stream;
      Failed : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   end record;

   overriding procedure Write
     (Sink   : in out File_Zip_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Status : out Archive.Archives.Errors.Error_Code);

   overriding procedure Write
     (Sink   : in out File_Tar_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);

   overriding procedure Write
     (Sink   : in out File_Tar_Gzip_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);

   overriding procedure Write
     (Sink   : in out File_Zip_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Status : out Archive.Archives.Errors.Error_Code)
   is
   begin
      Ada.Streams.Stream_IO.Write (Sink.File, Data);
      Status := Archive.Archives.Errors.Ok;
   exception
      when others =>
         Status := Archive.Archives.Errors.Write_Failed;
   end Write;

   procedure Write_Zlib_Bytes
     (File   : in out Ada.Streams.Stream_IO.File_Type;
      Bytes  : Zlib.Byte_Array;
      Status : out Archive.Archives.Errors.Error_Code)
   is
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
   begin
      Status := Archive.Archives.Errors.Ok;
      if Bytes'Length = 0 then
         return;
      end if;

      for Index in Bytes'Range loop
         Data (Ada.Streams.Stream_Element_Offset (Index - Bytes'First + 1)) :=
           Ada.Streams.Stream_Element (Bytes (Index));
      end loop;
      Ada.Streams.Stream_IO.Write (File, Data);
   exception
      when others =>
         Status := Archive.Archives.Errors.Write_Failed;
   end Write_Zlib_Bytes;

   overriding procedure Write
     (Sink   : in out File_Tar_Gzip_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status)
   is
      Input : Zlib.Byte_Array (1 .. Natural (Data'Length));
      Pos   : Natural := 1;
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   begin
      if Sink.Failed /= Archive.Archives.Errors.Ok then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      end if;

      for Item of Data loop
         Input (Pos) := Zlib.Byte (Item);
         Pos := Pos + 1;
      end loop;

      declare
         Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
           Archive.Compression.Zlib.Append (Sink.Stream, Input);
      begin
         if Step.Status /= Archive.Archives.Errors.Ok then
            Sink.Failed := Step.Status;
            Result := (Code => Tarlib.Errors.Output_Failure);
            return;
         end if;

         Write_Zlib_Bytes (Sink.File, Step.Bytes, Write_Status);
         if Write_Status /= Archive.Archives.Errors.Ok then
            Sink.Failed := Write_Status;
            Result := (Code => Tarlib.Errors.Output_Failure);
         else
            Result := Tarlib.Errors.OK;
         end if;
      end;
   exception
      when others =>
         Sink.Failed := Archive.Archives.Errors.Write_Failed;
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Write;

   function Finish_Tar_Gzip_Sink
     (Sink : in out File_Tar_Gzip_Sink)
      return Archive.Archives.Errors.Error_Code
   is
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   begin
      if Sink.Failed /= Archive.Archives.Errors.Ok then
         return Sink.Failed;
      end if;

      declare
         Final : constant Archive.Compression.Zlib.Stream_Step_Result :=
           Archive.Compression.Zlib.Finish (Sink.Stream);
         Closed : Archive.Compression.Zlib.Stream_Close_Result;
      begin
         if Final.Status /= Archive.Archives.Errors.Ok then
            return Final.Status;
         end if;

         Write_Zlib_Bytes (Sink.File, Final.Bytes, Write_Status);
         if Write_Status /= Archive.Archives.Errors.Ok then
            return Write_Status;
         end if;

         Closed := Archive.Compression.Zlib.Close (Sink.Stream);
         if Closed.Status /= Archive.Archives.Errors.Ok then
            return Closed.Status;
         end if;
      end;

      return Archive.Archives.Errors.Ok;
   exception
      when others =>
         return Archive.Archives.Errors.Write_Failed;
   end Finish_Tar_Gzip_Sink;

   overriding procedure Write
     (Sink   : in out File_Tar_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status)
   is
   begin
      Ada.Streams.Stream_IO.Write (Sink.File, Data);
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Write;

   function Parent_Directory (Path : String) return String is
   begin
      for Index in reverse Path'Range loop
         if Path (Index) = '/' then
            if Index = Path'First then
               return "/";
            end if;
            return Path (Path'First .. Index - 1);
         end if;
      end loop;
      return ".";
   end Parent_Directory;

   function Hex_Digit (Value : Natural) return Character is
      Hex_Chars : constant String := "0123456789abcdef";
   begin
      return Hex_Chars (Hex_Chars'First + Value);
   end Hex_Digit;

   function Hex_Image (Value : Temp_Nonce) return String is
      Result : String (1 .. 8);
      Work   : Natural := Natural (Value);
   begin
      for Index in reverse Result'Range loop
         Result (Index) := Hex_Digit (Work mod 16);
         Work := Work / 16;
      end loop;
      return Result;
   end Hex_Image;

   function Candidate_Sibling
     (Destination_Path : String;
      Role             : String;
      Nonce            : Temp_Nonce)
      return String
   is
   begin
      return Destination_Path & ".archive-" & Role & "-" & Hex_Image (Nonce);
   end Candidate_Sibling;

   function Fresh_Sibling_Path
     (Root             : String;
      Destination_Path : String;
      Role             : String)
      return String
   is
      Candidate : String :=
        Candidate_Sibling
          (Destination_Path, Role, Temp_Nonce_Random.Random (Temp_Generator));
   begin
      for Attempt in 1 .. 64 loop
         Candidate :=
           Candidate_Sibling
             (Destination_Path, Role, Temp_Nonce_Random.Random (Temp_Generator));
         if Archive.Temporary_Resources.Under_Root (Root, Candidate)
           and then not Ada.Directories.Exists (Candidate)
         then
            return Candidate;
         end if;
      end loop;

      return "";
   end Fresh_Sibling_Path;

   function Verify_Staged_Archive
     (Path            : String;
      Expected_Format : Archive.Archives.Formats.Format_Id;
      Source_Name     : String)
      return Boolean
   is
      Status : constant Archive.Archives.Errors.Error_Code :=
        Archive.Archives.Readers.Dispatch.Verify_File
          (Path, Expected_Format, Source_Name => Source_Name);
   begin
      return Status = Archive.Archives.Errors.Ok;
   end Verify_Staged_Archive;

   function Preflight
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Root             : String;
      Overwrite        : Boolean;
      Cancelled        : Boolean)
      return Archive.Writes.Results.Write_Status
   is
   begin
      if Plan.Status /= Archive.Writes.Plans.Write_Plan_Ready then
         return Archive.Writes.Results.Write_Blocked_By_Plan;
      elsif Cancelled then
         return Archive.Writes.Results.Write_Cancelled;
      elsif not Archive.Temporary_Resources.Under_Root (Root, Destination_Path) then
         return Archive.Writes.Results.Write_Failed_Containment;
      elsif Ada.Directories.Exists (Destination_Path) and then not Overwrite then
         return Archive.Writes.Results.Write_Blocked_By_Plan;
      else
         return Archive.Writes.Results.Write_Completed;
      end if;
   end Preflight;

   procedure Copy_File_Chunked
     (Source_Path : String;
      Target_Path : String;
      OK          : out Boolean)
   is
      Input  : Ada.Streams.Stream_IO.File_Type;
      Output : Ada.Streams.Stream_IO.File_Type;
      Data   : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
      Last   : Ada.Streams.Stream_Element_Offset := 0;
   begin
      OK := False;
      Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Source_Path);
      Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Target_Path);
      loop
         Ada.Streams.Stream_IO.Read (Input, Data, Last);
         exit when Last < Data'First;
         Ada.Streams.Stream_IO.Write (Output, Data (Data'First .. Last));
         exit when Last < Data'Last;
      end loop;
      Ada.Streams.Stream_IO.Close (Input);
      Ada.Streams.Stream_IO.Close (Output);
      OK := True;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Input) then
            Ada.Streams.Stream_IO.Close (Input);
         end if;
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         OK := False;
   end Copy_File_Chunked;

   function Finalize_Staged_Archive
     (Destination_Path : String;
      Temp             : String;
      Root             : String;
      Overwrite        : Boolean;
      Expected_Format  : Archive.Archives.Formats.Format_Id;
      Source_Name      : String;
      Cancelled        : Boolean)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      if Cancelled then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Cancelled);
      elsif not Verify_Staged_Archive (Temp, Expected_Format, Source_Name) then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Verification);
      end if;

      if not Archive.Temporary_Resources.Under_Root (Root, Destination_Path) then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Containment);
      end if;

      if Ada.Directories.Exists (Destination_Path) then
         if not Overwrite then
            if Ada.Directories.Exists (Temp) then
               Ada.Directories.Delete_File (Temp);
            end if;
            return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
         end if;

         declare
            Backup : constant String :=
              Fresh_Sibling_Path (Root, Destination_Path, "old");
         begin
            if Backup = "" then
               if Ada.Directories.Exists (Temp) then
                  Ada.Directories.Delete_File (Temp);
               end if;
               return (Status => Archive.Writes.Results.Write_Failed_Publish);
            end if;

            Ada.Directories.Rename (Destination_Path, Backup);
            begin
               Ada.Directories.Rename (Temp, Destination_Path);
               Ada.Directories.Delete_File (Backup);
            exception
               when others =>
                  if Ada.Directories.Exists (Destination_Path) then
                     Ada.Directories.Delete_File (Destination_Path);
                  end if;
                  if Ada.Directories.Exists (Backup) then
                     Ada.Directories.Rename (Backup, Destination_Path);
                  end if;
                  return (Status => Archive.Writes.Results.Write_Failed_Publish);
            end;
         end;
      else
         Ada.Directories.Rename (Temp, Destination_Path);
      end if;

      return (Status => Archive.Writes.Results.Write_Completed);
   exception
      when others =>
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Publish);
   end Finalize_Staged_Archive;

   function Publish_Archive_From_File
     (Destination_Path    : String;
      Plan                : Archive.Writes.Plans.Write_Plan;
      Payload_Source_Path : String;
      Overwrite           : Boolean := False;
      Expected_Format     : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format;
      Source_Name         : String := "";
      Cancelled           : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      OK : Boolean := False;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      elsif not Ada.Directories.Exists (Payload_Source_Path) then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Copy_File_Chunked (Payload_Source_Path, Temp, OK);
      if not OK then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite, Expected_Format, Source_Name,
         Cancelled);
   exception
      when others =>
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Archive_From_File;

   function Publish_Zip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Deflate          : Boolean;
      Source_Path      : String := "";
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Sink : File_Zip_Sink;
      Build_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Create (Sink.File, Ada.Streams.Stream_IO.Out_File, Temp);
      Build_Status :=
        (if Deflate
         then
           (if Source_Path = ""
            then Archive.Writes.Zip.Build_Deflate_Stream (Plan, Sink)
            else Archive.Writes.Zip.Build_Deflate_Stream
              (Plan, Sink, Source_Path, Source_Name))
         else
           (if Source_Path = ""
            then Archive.Writes.Zip.Build_Stored_Stream (Plan, Sink)
            else Archive.Writes.Zip.Build_Stored_Stream
              (Plan, Sink, Source_Path, Source_Name)));
      Ada.Streams.Stream_IO.Close (Sink.File);

      if Build_Status /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return
           (Status =>
              (if Build_Status = Archive.Archives.Errors.Write_Failed
               then Archive.Writes.Results.Write_Failed_Staging
               else Archive.Writes.Results.Write_Blocked_By_Plan));
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Zip_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Sink.File) then
            Ada.Streams.Stream_IO.Close (Sink.File);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Zip;

   function Publish_Zip_Stored
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip
        (Destination_Path, Plan, Deflate => False,
         Overwrite => Overwrite, Cancelled => Cancelled);
   end Publish_Zip_Stored;

   function Publish_Zip_Stored
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip
        (Destination_Path, Plan, Deflate => False,
         Source_Path => Source_Path,
         Source_Name => Source_Name,
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Zip_Stored;

   function Publish_Zip_Deflate
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip
        (Destination_Path, Plan, Deflate => True,
         Overwrite => Overwrite, Cancelled => Cancelled);
   end Publish_Zip_Deflate;

   function Publish_Zip_Deflate
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip
        (Destination_Path, Plan, Deflate => True,
         Source_Path => Source_Path,
         Source_Name => Source_Name,
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Zip_Deflate;

   function Publish_Tar_Internal
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Sink : File_Tar_Sink;
      Build_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Create (Sink.File, Ada.Streams.Stream_IO.Out_File, Temp);
      Build_Status :=
        (if Source_Path = ""
         then Archive.Writes.Tar.Build_Stream (Plan, Sink)
         else Archive.Writes.Tar.Build_Stream (Plan, Sink, Source_Path));
      Ada.Streams.Stream_IO.Close (Sink.File);

      if Build_Status /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return
           (Status =>
              (if Build_Status = Archive.Archives.Errors.Write_Failed
               then Archive.Writes.Results.Write_Failed_Staging
               else Archive.Writes.Results.Write_Blocked_By_Plan));
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Tar_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Sink.File) then
            Ada.Streams.Stream_IO.Close (Sink.File);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Tar_Internal;

   function Publish_Tar
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Tar_Internal
        (Destination_Path, Plan,
         Source_Path => "",
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Tar;

   function Publish_Tar
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Tar_Internal
        (Destination_Path, Plan,
         Source_Path => Source_Path,
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Tar;

   function Stage_Gzip_As_Tar
     (Source_Path : String;
      Target_Path : String)
      return Archive.Archives.Errors.Error_Code
   is
      Input  : Ada.Streams.Stream_IO.File_Type;
      Output : Ada.Streams.Stream_IO.File_Type;
      Stream : Archive.Compression.Zlib.Inflate_Stream;
      Data   : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
      Last   : Ada.Streams.Stream_Element_Offset := 0;
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;

      function To_Bytes
        (Slice : Ada.Streams.Stream_Element_Array)
         return Zlib.Byte_Array
      is
         Result : Zlib.Byte_Array (1 .. Natural (Slice'Length));
         Pos : Natural := 1;
      begin
         for Item of Slice loop
            Result (Pos) := Zlib.Byte (Item);
            Pos := Pos + 1;
         end loop;
         return Result;
      end To_Bytes;

      procedure Write_Output (Bytes : Zlib.Byte_Array) is
      begin
         Write_Zlib_Bytes (Output, Bytes, Write_Status);
      end Write_Output;
   begin
      Archive.Compression.Zlib.Open
        (Stream,
         Archive.Compression.Zlib.Gzip_Wrapped,
         Limits =>
           (Max_Output_Bytes => Archive.Types.Uncompressed_Size
              (Archive.Resource_Limits.Default_Configured
                 (Archive.Resource_Limits.Temporary_Backing_Bytes)),
            Max_Ratio => 1_000));
      Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Source_Path);
      Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Target_Path);

      loop
         Ada.Streams.Stream_IO.Read (Input, Data, Last);
         exit when Last < Data'First;
         declare
            Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Append
                (Stream, To_Bytes (Data (Data'First .. Last)));
         begin
            if Step.Status /= Archive.Archives.Errors.Ok then
               Ada.Streams.Stream_IO.Close (Input);
               Ada.Streams.Stream_IO.Close (Output);
               declare
                  Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                    Archive.Compression.Zlib.Close (Stream);
               begin
                  pragma Unreferenced (Closed);
               end;
               return Step.Status;
            end if;
            Write_Output (Step.Bytes);
            if Write_Status /= Archive.Archives.Errors.Ok then
               Ada.Streams.Stream_IO.Close (Input);
               Ada.Streams.Stream_IO.Close (Output);
               declare
                  Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                    Archive.Compression.Zlib.Close (Stream);
               begin
                  pragma Unreferenced (Closed);
               end;
               return Write_Status;
            end if;
         end;
         exit when Last < Data'Last;
      end loop;
      Ada.Streams.Stream_IO.Close (Input);

      declare
         Final : constant Archive.Compression.Zlib.Stream_Step_Result :=
           Archive.Compression.Zlib.Finish (Stream);
         Closed : Archive.Compression.Zlib.Stream_Close_Result;
      begin
         if Final.Status /= Archive.Archives.Errors.Ok then
            Ada.Streams.Stream_IO.Close (Output);
            Closed := Archive.Compression.Zlib.Close (Stream);
            return Final.Status;
         end if;
         Write_Output (Final.Bytes);
         Ada.Streams.Stream_IO.Close (Output);
         Closed := Archive.Compression.Zlib.Close (Stream);
         if Write_Status /= Archive.Archives.Errors.Ok then
            return Write_Status;
         elsif Closed.Status /= Archive.Archives.Errors.Ok then
            return Closed.Status;
         else
            return Archive.Archives.Errors.Ok;
         end if;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Input) then
            Ada.Streams.Stream_IO.Close (Input);
         end if;
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         return Archive.Archives.Errors.Read_Failed;
   end Stage_Gzip_As_Tar;

   function Publish_Tar_Gzip_Internal
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Sink : File_Tar_Gzip_Sink;
      Build_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Finish_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Source_Tar : constant String :=
        Fresh_Sibling_Path (Root, Destination_Path, "source-tar");
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" or else (Source_Path /= "" and then Source_Tar = "") then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Create (Sink.File, Ada.Streams.Stream_IO.Out_File, Temp);
      Archive.Compression.Zlib.Open
        (Sink.Stream,
         Archive.Compression.Zlib.Gzip_Wrapped,
         Max_Output_Bytes => Archive.Types.Compressed_Size'Last);

      if Source_Path /= "" then
         Build_Status := Stage_Gzip_As_Tar (Source_Path, Source_Tar);
      end if;

      if Build_Status = Archive.Archives.Errors.Ok then
         Build_Status :=
           (if Source_Path = ""
            then Archive.Writes.Tar.Build_Stream (Plan, Sink)
            else Archive.Writes.Tar.Build_Stream (Plan, Sink, Source_Tar));
         Finish_Status := Finish_Tar_Gzip_Sink (Sink);
      end if;
      Ada.Streams.Stream_IO.Close (Sink.File);

      if Ada.Directories.Exists (Source_Tar) then
         Ada.Directories.Delete_File (Source_Tar);
      end if;

      if Build_Status /= Archive.Archives.Errors.Ok
        or else Finish_Status /= Archive.Archives.Errors.Ok
      then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return
           (Status =>
              (if Build_Status = Archive.Archives.Errors.Write_Failed
                 or else Finish_Status = Archive.Archives.Errors.Write_Failed
               then Archive.Writes.Results.Write_Failed_Staging
               else Archive.Writes.Results.Write_Blocked_By_Plan));
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Tar_GZip_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Sink.File) then
            Ada.Streams.Stream_IO.Close (Sink.File);
         end if;
         if Ada.Directories.Exists (Source_Tar) then
            begin
               Ada.Directories.Delete_File (Source_Tar);
            exception
               when others =>
                  null;
            end;
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Tar_Gzip_Internal;

   function Publish_Tar_Gzip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Tar_Gzip_Internal
        (Destination_Path, Plan,
         Source_Path => "",
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Tar_Gzip;

   function Publish_Tar_Gzip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Tar_Gzip_Internal
        (Destination_Path, Plan,
         Source_Path => Source_Path,
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Tar_Gzip;

   function Publish_Gzip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Input  : Ada.Streams.Stream_IO.File_Type;
      Output : Ada.Streams.Stream_IO.File_Type;
      Stream : Archive.Compression.Zlib.Deflate_Stream;
      Data   : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
      Last   : Ada.Streams.Stream_Element_Offset := 0;
      Source : Ada.Strings.Unbounded.Unbounded_String;
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;

      function To_Bytes
        (Slice : Ada.Streams.Stream_Element_Array)
         return Zlib.Byte_Array
      is
         Result : Zlib.Byte_Array (1 .. Natural (Slice'Length));
         Pos    : Natural := 1;
      begin
         for Item of Slice loop
            Result (Pos) := Zlib.Byte (Item);
            Pos := Pos + 1;
         end loop;
         return Result;
      end To_Bytes;

      procedure Fail_Cleanup is
      begin
         if Ada.Streams.Stream_IO.Is_Open (Input) then
            Ada.Streams.Stream_IO.Close (Input);
         end if;
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
      exception
         when others =>
            null;
      end Fail_Cleanup;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      if Natural (Plan.Changes.Length) /= 1 then
         return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
      end if;

      declare
         Change : constant Archive.Writes.Plans.Planned_Change :=
           Plan.Changes.Element (Plan.Changes.First_Index);
      begin
         if Change.Decision /= Archive.Writes.Plans.Entry_Ready
           or else Change.Request.Action not in Archive.Writes.Plans.Add_File
             | Archive.Writes.Plans.Replace_File
           or else Ada.Strings.Unbounded.To_String (Change.Request.Host_Source) = ""
         then
            return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
         end if;

         Source := Change.Request.Host_Source;
      end;

      if not Ada.Directories.Exists (Ada.Strings.Unbounded.To_String (Source)) then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Open
        (Input, Ada.Streams.Stream_IO.In_File,
         Ada.Strings.Unbounded.To_String (Source));
      Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Temp);
      Archive.Compression.Zlib.Open
        (Stream,
         Archive.Compression.Zlib.Gzip_Wrapped,
         Max_Output_Bytes => Archive.Types.Compressed_Size'Last);

      loop
         Ada.Streams.Stream_IO.Read (Input, Data, Last);
         exit when Last < Data'First;
         declare
            Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Append
                (Stream, To_Bytes (Data (Data'First .. Last)));
         begin
            if Step.Status /= Archive.Archives.Errors.Ok then
               declare
                  Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                    Archive.Compression.Zlib.Close (Stream);
               begin
                  pragma Unreferenced (Closed);
               end;
               Fail_Cleanup;
               return (Status => Archive.Writes.Results.Write_Failed_Staging);
            end if;

            Write_Zlib_Bytes (Output, Step.Bytes, Write_Status);
            if Write_Status /= Archive.Archives.Errors.Ok then
               declare
                  Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                    Archive.Compression.Zlib.Close (Stream);
               begin
                  pragma Unreferenced (Closed);
               end;
               Fail_Cleanup;
               return (Status => Archive.Writes.Results.Write_Failed_Staging);
            end if;
         end;
         exit when Last < Data'Last;
      end loop;
      Ada.Streams.Stream_IO.Close (Input);

      declare
         Final : constant Archive.Compression.Zlib.Stream_Step_Result :=
           Archive.Compression.Zlib.Finish (Stream);
         Closed : Archive.Compression.Zlib.Stream_Close_Result;
      begin
         if Final.Status /= Archive.Archives.Errors.Ok then
            Closed := Archive.Compression.Zlib.Close (Stream);
            Fail_Cleanup;
            return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end if;

         Write_Zlib_Bytes (Output, Final.Bytes, Write_Status);
         Ada.Streams.Stream_IO.Close (Output);
         Closed := Archive.Compression.Zlib.Close (Stream);
         if Write_Status /= Archive.Archives.Errors.Ok
           or else Closed.Status /= Archive.Archives.Errors.Ok
         then
            Fail_Cleanup;
            return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end if;
      end;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.GZip_Format, Destination_Path, Cancelled);
   exception
      when others =>
         Fail_Cleanup;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Gzip;
begin
   Temp_Nonce_Random.Reset (Temp_Generator);
end Archive.Writes.Execution;
