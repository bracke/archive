with Ada.Containers.Vectors;

package Archive.View_Snapshots.Columns is
   type Column_Id is
     (Name_Column,
      Kind_Column,
      Uncompressed_Size_Column,
      Compressed_Size_Column,
      Compression_Ratio_Column,
      Modified_Time_Column,
      Compression_Method_Column,
      Archive_Position_Column,
      Original_Path_Column,
      Owner_Column,
      Group_Column,
      Permissions_Column,
      Integrity_Column,
      Path_Safety_Column,
      Link_Target_Column);

   subtype Registered_Column_Id is Column_Id range Name_Column .. Link_Target_Column;

   type Column_Descriptor is record
      Id           : Column_Id := Name_Column;
      Stable_Token : String (1 .. 32);
      Token_Length : Natural := 0;
      Name_Key     : String (1 .. 64);
      Key_Length   : Natural := 0;
      Sortable     : Boolean := False;
      Sort_Field   : Archive.View_Snapshots.Sort_Field := Archive.View_Snapshots.Sort_By_Name;
      Default_Show : Boolean := False;
   end record;

   package Column_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Column_Id);

   function Token (Id : Column_Id) return String;
   function Name_Key (Id : Column_Id) return String;
   function Is_Sortable (Id : Column_Id) return Boolean;
   function Sort_Field_For (Id : Column_Id) return Archive.View_Snapshots.Sort_Field;
   function Default_Visible (Id : Column_Id) return Boolean;
   function Id_For_Token (Token_Text : String) return Column_Id;
   function Contains (Token_Text : String) return Boolean;
   function Column_Count return Natural;
   function Default_Columns return Column_Vectors.Vector;
end Archive.View_Snapshots.Columns;
