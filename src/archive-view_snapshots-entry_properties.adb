with Ada.Strings.Unbounded;

package body Archive.View_Snapshots.Entry_Properties is
   use Ada.Strings.Unbounded;

   function Build
     (Item             : Archive.Archives.Entries.Archive_Entry;
      Archive_Writable : Boolean := True)
      return Entry_Property_Snapshot
   is
      Caps : constant Archive.Archives.Capabilities.Entry_Capabilities :=
        Archive.Archives.Capabilities.For_Entry (Item, Archive_Writable);
   begin
      return
        (Id              => Item.Id,
         Name            => Item.Display_Name,
         Original_Path   => Item.Original_Path,
         Kind            => Item.Kind,
         Method          => Item.Method,
         Safety          => Item.Safety,
         Integrity       => Item.Integrity,
         Can_Preview     => Caps.Can_Preview,
         Can_Extract     => Caps.Can_Extract,
         Can_Verify      => Caps.Can_Verify,
         Can_Open_Externally => Caps.Can_Open_Externally,
         Can_Follow_Link => Caps.Can_Follow_Link,
         Can_Add         => Caps.Can_Add,
         Can_Replace     => Caps.Can_Replace,
         Can_Remove      => Caps.Can_Remove,
         Can_Rename      => Caps.Can_Rename,
         Reason          => Caps.Reason,
         Preview_Reason  => Caps.Preview_Reason,
         Extract_Reason  => Caps.Extract_Reason,
         Verify_Reason   => Caps.Verify_Reason,
         Open_External_Reason => Caps.Open_External_Reason,
         Follow_Link_Reason => Caps.Follow_Link_Reason,
         Add_Reason      => Caps.Add_Reason,
         Replace_Reason  => Caps.Replace_Reason,
         Remove_Reason   => Caps.Remove_Reason,
         Rename_Reason   => Caps.Rename_Reason,
         Unavailable_Key => To_Unbounded_String
           (Archive.Archives.Capabilities.Unavailable_Key (Caps.Reason)));
   end Build;
end Archive.View_Snapshots.Entry_Properties;
