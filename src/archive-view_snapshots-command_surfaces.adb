with Ada.Strings.Unbounded;

with Archive.Localization;

package body Archive.View_Snapshots.Command_Surfaces is
   use Ada.Strings.Unbounded;
   use type Archive.Commands.Command_Category;

   function Category_Name_Key (Category : Archive.Commands.Command_Category) return String is
   begin
      case Category is
         when Archive.Commands.File_Category =>
            return "menu.file";
         when Archive.Commands.Edit_Category =>
            return "menu.edit";
         when Archive.Commands.View_Category =>
            return "menu.view";
         when Archive.Commands.Navigate_Category =>
            return "menu.navigate";
         when Archive.Commands.Tools_Category =>
            return "menu.tools";
         when Archive.Commands.Settings_Category =>
            return "menu.settings";
         when Archive.Commands.Application_Category =>
            return "menu.application";
      end case;
   end Category_Name_Key;

   function Row_For
     (Id     : Archive.Commands.Command_Id;
      Model  : Archive.Model.Application_Model;
      Locale : String)
      return Surface_Command
   is
      Descriptor : constant Archive.Commands.Command_Descriptor :=
        Archive.Commands.Descriptor (Id, Model);
      Unavailable_Key : constant String :=
        Archive.Commands.To_String (Descriptor.Unavailable_Key);
      Unavailable : constant String :=
        (if Unavailable_Key = "" then ""
         else Archive.Localization.Text (Unavailable_Key, Locale));
   begin
      return
        (Id               => Id,
         Name             =>
           To_Unbounded_String
             (Archive.Localization.Text
                (Archive.Commands.To_String (Descriptor.Name_Key), Locale)),
         Description      =>
           To_Unbounded_String
             (Archive.Localization.Text
                (Archive.Commands.To_String (Descriptor.Description_Key), Locale)),
         Unavailable_Text => To_Unbounded_String (Unavailable),
         Icon_Name        =>
           To_Unbounded_String (Archive.Commands.To_String (Descriptor.Icon_Name)),
         Enabled          => Descriptor.Enabled);
   end Row_For;

   function Build_Menus
     (Model  : Archive.Model.Application_Model;
      Locale : Archive.Types.UString)
      return Menu_Snapshot
   is
      Result : Menu_Snapshot;
      Locale_Text : constant String := To_String (Locale);
   begin
      for Category in Archive.Commands.Command_Category loop
         declare
            Section : Menu_Section :=
              (Category => Category,
               Name     =>
                 To_Unbounded_String
                   (Archive.Localization.Text (Category_Name_Key (Category), Locale_Text)),
               Commands => Surface_Command_Vectors.Empty_Vector);
         begin
            for Id in Archive.Commands.Registered_Command_Id loop
               if Archive.Commands.Category_For (Id) = Category then
                  Section.Commands.Append (Row_For (Id, Model, Locale_Text));
               end if;
            end loop;

            if not Section.Commands.Is_Empty then
               Result.Sections.Append (Section);
            end if;
         end;
      end loop;
      return Result;
   end Build_Menus;

   function Build_Toolbar
     (Model  : Archive.Model.Application_Model;
      Locale : Archive.Types.UString)
      return Toolbar_Snapshot
   is
      Result : Toolbar_Snapshot;
      Locale_Text : constant String := To_String (Locale);
      Toolbar_Commands : constant array (Positive range <>) of Archive.Commands.Command_Id :=
        [Archive.Commands.Open_Archive_Command,
         Archive.Commands.New_Archive_Command,
         Archive.Commands.Reload_Archive_Command,
         Archive.Commands.Add_Files_Command,
         Archive.Commands.Save_Archive_Command,
         Archive.Commands.Extract_Selected_Command,
         Archive.Commands.Verify_Archive_Command,
         Archive.Commands.Toggle_Preview_Command];
   begin
      for Id of Toolbar_Commands loop
         Result.Commands.Append (Row_For (Id, Model, Locale_Text));
      end loop;
      return Result;
   end Build_Toolbar;
end Archive.View_Snapshots.Command_Surfaces;
