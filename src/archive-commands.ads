with Archive.Model;
with Guikit.Input;

package Archive.Commands is
   type Command_Id is
     (No_Command,
      Open_Archive_Command,
      New_Archive_Command,
      Close_Archive_Command,
      Reload_Archive_Command,
      Open_Recent_Archive_Command,
      Save_Archive_Command,
      Save_Archive_As_Command,
      Discard_Changes_Command,
      Add_Files_Command,
      Add_Directory_Command,
      Replace_Selected_Command,
      Remove_Selected_Command,
      Rename_Selected_Command,
      Navigate_Back_Command,
      Navigate_Forward_Command,
      Navigate_Parent_Command,
      Navigate_Root_Command,
      Activate_Entry_Command,
      Preview_Entry_Command,
      Extract_Selected_Command,
      Extract_All_Command,
      Cancel_Extraction_Command,
      Verify_Archive_Command,
      Copy_Entry_Path_Command,
      Copy_Entry_Information_Command,
      Show_Archive_Properties_Command,
      Show_Entry_Properties_Command,
      Select_Grid_View_Command,
      Select_Compact_View_Command,
      Select_Details_View_Command,
      Change_Sorting_Command,
      Clear_Filter_Command,
      Toggle_Preview_Command,
      Open_Settings_Command,
      Open_Command_Palette_Command,
      Quit_Command);

   subtype Registered_Command_Id is Command_Id range Open_Archive_Command .. Quit_Command;

   type Shortcut is record
      Present   : Boolean := False;
      Key       : Guikit.Input.Key_Code := Guikit.Input.Key_Unknown;
      Modifiers : Guikit.Input.Modifier_Set := Guikit.Input.No_Modifiers;
   end record;

   type Command_Category is
     (File_Category,
      Edit_Category,
      View_Category,
      Navigate_Category,
      Tools_Category,
      Settings_Category,
      Application_Category);

   type Bounded_Text_64 is record
      Text   : String (1 .. 64);
      Length : Natural := 0;
   end record;

   type Command_Descriptor is record
      Id                     : Command_Id := No_Command;
      Identifier             : Bounded_Text_64;
      Name_Key               : Bounded_Text_64;
      Description_Key        : Bounded_Text_64;
      Unavailable_Key        : Bounded_Text_64;
      Icon_Name              : Bounded_Text_64;
      Category               : Command_Category := Application_Category;
      Default_Shortcut       : Shortcut;
      Enabled                : Boolean := False;
   end record;

   function To_String (Value : Bounded_Text_64) return String;
   function Identifier (Id : Command_Id) return String;
   function Name_Key (Id : Command_Id) return String;
   function Description_Key (Id : Command_Id) return String;
   function Unavailable_Key (Id : Command_Id; Model : Archive.Model.Application_Model) return String;
   function Icon_Name (Id : Command_Id) return String;
   function Category_For (Id : Command_Id) return Command_Category;
   function Shortcut_For (Id : Command_Id) return Shortcut;
   function Descriptor
     (Id    : Command_Id;
      Model : Archive.Model.Application_Model)
      return Command_Descriptor;
   function Command_Count return Natural;
   function Contains (Identifier_Text : String) return Boolean;
   function Id_For_Identifier (Identifier_Text : String) return Command_Id;
   function Is_Enabled (Id : Command_Id; Model : Archive.Model.Application_Model) return Boolean;
   procedure Execute (Id : Command_Id; Model : in out Archive.Model.Application_Model);
end Archive.Commands;
