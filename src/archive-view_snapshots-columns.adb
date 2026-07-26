package body Archive.View_Snapshots.Columns is
   function Make
     (Id           : Column_Id;
      Stable_Token : String;
      Name_Key     : String;
      Sortable     : Boolean;
      Sort_Field   : Archive.View_Snapshots.Sort_Field;
      Default_Show : Boolean)
      return Column_Descriptor
   is
      Result : Column_Descriptor;
   begin
      Result.Id := Id;
      Result.Stable_Token (1 .. Stable_Token'Length) := Stable_Token;
      Result.Token_Length := Stable_Token'Length;
      Result.Name_Key (1 .. Name_Key'Length) := Name_Key;
      Result.Key_Length := Name_Key'Length;
      Result.Sortable := Sortable;
      Result.Sort_Field := Sort_Field;
      Result.Default_Show := Default_Show;
      return Result;
   end Make;

   function Descriptor (Id : Column_Id) return Column_Descriptor is
   begin
      case Id is
         when Name_Column =>
            return Make
              (Id, "name", "column.name", True,
               Archive.View_Snapshots.Sort_By_Name, True);
         when Kind_Column =>
            return Make
              (Id, "type", "column.type", True,
               Archive.View_Snapshots.Sort_By_Kind, True);
         when Uncompressed_Size_Column =>
            return Make
              (Id, "uncompressed_size", "column.uncompressed_size", True,
               Archive.View_Snapshots.Sort_By_Uncompressed_Size, True);
         when Compressed_Size_Column =>
            return Make
              (Id, "compressed_size", "column.compressed_size", True,
               Archive.View_Snapshots.Sort_By_Compressed_Size, False);
         when Compression_Ratio_Column =>
            return Make
              (Id, "compression_ratio", "column.compression_ratio", False,
               Archive.View_Snapshots.Sort_By_Name, False);
         when Modified_Time_Column =>
            return Make
              (Id, "modified_time", "column.modified_time", False,
               Archive.View_Snapshots.Sort_By_Name, True);
         when Compression_Method_Column =>
            return Make
              (Id, "compression_method", "column.compression_method", False,
               Archive.View_Snapshots.Sort_By_Name, True);
         when Archive_Position_Column =>
            return Make
              (Id, "archive_position", "column.archive_position", True,
               Archive.View_Snapshots.Sort_By_Archive_Order, False);
         when Original_Path_Column =>
            return Make
              (Id, "original_path", "column.original_path", False,
               Archive.View_Snapshots.Sort_By_Name, False);
         when Owner_Column =>
            return Make
              (Id, "owner", "column.owner", False,
               Archive.View_Snapshots.Sort_By_Name, False);
         when Group_Column =>
            return Make
              (Id, "group", "column.group", False,
               Archive.View_Snapshots.Sort_By_Name, False);
         when Permissions_Column =>
            return Make
              (Id, "permissions", "column.permissions", False,
               Archive.View_Snapshots.Sort_By_Name, False);
         when Integrity_Column =>
            return Make
              (Id, "integrity", "column.integrity", False,
               Archive.View_Snapshots.Sort_By_Name, True);
         when Path_Safety_Column =>
            return Make
              (Id, "path_safety", "column.path_safety", False,
               Archive.View_Snapshots.Sort_By_Name, True);
         when Link_Target_Column =>
            return Make
              (Id, "link_target", "column.link_target", False,
               Archive.View_Snapshots.Sort_By_Name, False);
      end case;
   end Descriptor;

   function Token (Id : Column_Id) return String is
      D : constant Column_Descriptor := Descriptor (Id);
   begin
      return D.Stable_Token (1 .. D.Token_Length);
   end Token;

   function Name_Key (Id : Column_Id) return String is
      D : constant Column_Descriptor := Descriptor (Id);
   begin
      return D.Name_Key (1 .. D.Key_Length);
   end Name_Key;

   function Is_Sortable (Id : Column_Id) return Boolean is
   begin
      return Descriptor (Id).Sortable;
   end Is_Sortable;

   function Sort_Field_For (Id : Column_Id) return Archive.View_Snapshots.Sort_Field is
   begin
      return Descriptor (Id).Sort_Field;
   end Sort_Field_For;

   function Default_Visible (Id : Column_Id) return Boolean is
   begin
      return Descriptor (Id).Default_Show;
   end Default_Visible;

   function Id_For_Token (Token_Text : String) return Column_Id is
   begin
      for Id in Registered_Column_Id loop
         if Token (Id) = Token_Text then
            return Id;
         end if;
      end loop;
      return Name_Column;
   end Id_For_Token;

   function Contains (Token_Text : String) return Boolean is
   begin
      for Id in Registered_Column_Id loop
         if Token (Id) = Token_Text then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Column_Count return Natural is
   begin
      return Registered_Column_Id'Pos (Registered_Column_Id'Last)
        - Registered_Column_Id'Pos (Registered_Column_Id'First) + 1;
   end Column_Count;

   function Default_Columns return Column_Vectors.Vector is
      Result : Column_Vectors.Vector;
   begin
      for Id in Registered_Column_Id loop
         if Default_Visible (Id) then
            Result.Append (Id);
         end if;
      end loop;
      return Result;
   end Default_Columns;
end Archive.View_Snapshots.Columns;
