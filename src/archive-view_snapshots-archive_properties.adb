with Ada.Strings.Unbounded;

package body Archive.View_Snapshots.Archive_Properties is
   use Ada.Strings.Unbounded;

   function Build
     (Format : Archive.Archives.Formats.Format_Id;
      Index  : Archive.Archives.Index.Archive_Index)
      return Archive_Property_Snapshot
   is
      Caps : constant Archive.Archives.Formats.Format_Capabilities :=
        Archive.Archives.Formats.Capabilities (Format);
   begin
      return
        (Format              => Format,
         Format_Name_Key     => To_Unbounded_String (Archive.Archives.Formats.Name_Key (Format)),
         Entry_Count         => Archive.Archives.Index.Entry_Count (Index),
         Physical_Count      => Archive.Archives.Index.Physical_Count (Index),
         Synthetic_Count     => Archive.Archives.Index.Synthetic_Count (Index),
         Can_Verify_Payload  => Caps.Can_Verify_Payload,
         Can_Open_Streams    => Caps.Can_Open_Entry_Streams,
         Supports_Duplicates => Caps.Supports_Duplicates);
   end Build;
end Archive.View_Snapshots.Archive_Properties;
