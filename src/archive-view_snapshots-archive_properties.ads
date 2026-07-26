with Archive.Archives.Formats;
with Archive.Archives.Index;
with Archive.Types;

package Archive.View_Snapshots.Archive_Properties is
   type Archive_Property_Snapshot is record
      Format              : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format;
      Format_Name_Key     : Archive.Types.UString;
      Entry_Count         : Natural := 0;
      Physical_Count      : Natural := 0;
      Synthetic_Count     : Natural := 0;
      Can_Verify_Payload  : Boolean := False;
      Can_Open_Streams    : Boolean := False;
      Supports_Duplicates : Boolean := False;
   end record;

   function Build
     (Format : Archive.Archives.Formats.Format_Id;
      Index  : Archive.Archives.Index.Archive_Index)
      return Archive_Property_Snapshot;
end Archive.View_Snapshots.Archive_Properties;
