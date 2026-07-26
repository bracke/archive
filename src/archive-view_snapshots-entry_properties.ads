with Archive.Archives.Entries;
with Archive.Archives.Capabilities;
with Archive.Types;

package Archive.View_Snapshots.Entry_Properties is
   type Entry_Property_Snapshot is record
      Id              : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Name            : Archive.Types.UString;
      Original_Path   : Archive.Types.UString;
      Kind            : Archive.Archives.Entries.Entry_Kind :=
        Archive.Archives.Entries.Unknown;
      Method          : Archive.Archives.Entries.Compression_Method :=
        Archive.Archives.Entries.Unknown_Compression;
      Safety          : Archive.Archives.Entries.Path_Safety :=
        Archive.Archives.Entries.Unsafe_Encoding;
      Integrity       : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Not_Checked;
      Can_Preview     : Boolean := False;
      Can_Extract     : Boolean := False;
      Can_Verify      : Boolean := False;
      Can_Open_Externally : Boolean := False;
      Can_Follow_Link : Boolean := False;
      Can_Add         : Boolean := False;
      Can_Replace     : Boolean := False;
      Can_Remove      : Boolean := False;
      Can_Rename      : Boolean := False;
      Reason          : Archive.Archives.Capabilities.Entry_Unavailable_Reason :=
        Archive.Archives.Capabilities.No_Entry_Selected;
      Preview_Reason  : Archive.Archives.Capabilities.Entry_Unavailable_Reason :=
        Archive.Archives.Capabilities.No_Entry_Selected;
      Extract_Reason  : Archive.Archives.Capabilities.Entry_Unavailable_Reason :=
        Archive.Archives.Capabilities.No_Entry_Selected;
      Verify_Reason   : Archive.Archives.Capabilities.Entry_Unavailable_Reason :=
        Archive.Archives.Capabilities.No_Entry_Selected;
      Open_External_Reason : Archive.Archives.Capabilities.Entry_Unavailable_Reason :=
        Archive.Archives.Capabilities.No_Entry_Selected;
      Follow_Link_Reason : Archive.Archives.Capabilities.Entry_Unavailable_Reason :=
        Archive.Archives.Capabilities.No_Entry_Selected;
      Add_Reason      : Archive.Archives.Capabilities.Entry_Unavailable_Reason :=
        Archive.Archives.Capabilities.No_Entry_Selected;
      Replace_Reason  : Archive.Archives.Capabilities.Entry_Unavailable_Reason :=
        Archive.Archives.Capabilities.No_Entry_Selected;
      Remove_Reason   : Archive.Archives.Capabilities.Entry_Unavailable_Reason :=
        Archive.Archives.Capabilities.No_Entry_Selected;
      Rename_Reason   : Archive.Archives.Capabilities.Entry_Unavailable_Reason :=
        Archive.Archives.Capabilities.No_Entry_Selected;
      Unavailable_Key : Archive.Types.UString;
   end record;

   function Build
     (Item             : Archive.Archives.Entries.Archive_Entry;
      Archive_Writable : Boolean := True)
      return Entry_Property_Snapshot;
end Archive.View_Snapshots.Entry_Properties;
