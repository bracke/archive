with Archive.Archives.Entries;

package Archive.Archives.Capabilities is
   type Entry_Unavailable_Reason is
     (Available,
      No_Entry_Selected,
      Encrypted_Entry,
      Unsupported_Method,
      Unsafe_Path,
      Unsupported_Entry_Kind,
      Unsupported_Write_Action);

   type Entry_Capabilities is record
      Can_Preview         : Boolean := False;
      Can_Extract         : Boolean := False;
      Can_Verify          : Boolean := False;
      Can_Open_Externally : Boolean := False;
      Can_Follow_Link     : Boolean := False;
      Can_Add             : Boolean := False;
      Can_Replace         : Boolean := False;
      Can_Remove          : Boolean := False;
      Can_Rename          : Boolean := False;
      Reason              : Entry_Unavailable_Reason := No_Entry_Selected;
      Preview_Reason      : Entry_Unavailable_Reason := No_Entry_Selected;
      Extract_Reason      : Entry_Unavailable_Reason := No_Entry_Selected;
      Verify_Reason       : Entry_Unavailable_Reason := No_Entry_Selected;
      Open_External_Reason : Entry_Unavailable_Reason := No_Entry_Selected;
      Follow_Link_Reason  : Entry_Unavailable_Reason := No_Entry_Selected;
      Add_Reason          : Entry_Unavailable_Reason := No_Entry_Selected;
      Replace_Reason      : Entry_Unavailable_Reason := No_Entry_Selected;
      Remove_Reason       : Entry_Unavailable_Reason := No_Entry_Selected;
      Rename_Reason       : Entry_Unavailable_Reason := No_Entry_Selected;
   end record;

   function Unavailable_Key (Reason : Entry_Unavailable_Reason) return String;

   function For_Entry
     (Item             : Archive.Archives.Entries.Archive_Entry;
      Archive_Writable : Boolean := True)
      return Entry_Capabilities;
end Archive.Archives.Capabilities;
