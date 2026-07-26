with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Archive.Localization;

package body Archive.View_Snapshots.Command_Palette is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   function Lower (Value : String) return String is
      Result : String := Value;
   begin
      for C of Result loop
         C := Ada.Characters.Handling.To_Lower (C);
      end loop;
      return Result;
   end Lower;

   function Matches
     (Name       : String;
      Identifier : String;
      Filter     : String)
      return Boolean
   is
      Needle : constant String := Lower (Filter);
   begin
      return Needle = ""
        or else Ada.Strings.Fixed.Index (Lower (Name), Needle) > 0
        or else Ada.Strings.Fixed.Index (Lower (Identifier), Needle) > 0;
   end Matches;

   function Build
     (Model   : Archive.Model.Application_Model;
      Request : Palette_Request)
      return Palette_Snapshot
   is
      Result : Palette_Snapshot;
      Locale : constant String := To_String (Request.Locale);
   begin
      for Id in Archive.Commands.Registered_Command_Id loop
         declare
            Descriptor : constant Archive.Commands.Command_Descriptor :=
              Archive.Commands.Descriptor (Id, Model);
            Identifier : constant String :=
              Archive.Commands.To_String (Descriptor.Identifier);
            Name : constant String :=
              Archive.Localization.Text
                (Archive.Commands.To_String (Descriptor.Name_Key), Locale);
            Description : constant String :=
              Archive.Localization.Text
                (Archive.Commands.To_String (Descriptor.Description_Key), Locale);
            Unavailable_Key : constant String :=
              Archive.Commands.To_String (Descriptor.Unavailable_Key);
            Unavailable : constant String :=
              (if Unavailable_Key = "" then ""
               else Archive.Localization.Text (Unavailable_Key, Locale));
         begin
            if Matches (Name, Identifier, To_String (Request.Filter_Text)) then
               if Result.Rows.Length < Ada.Containers.Count_Type (Request.Limit) then
                  Result.Rows.Append
                    (Command_Row'
                       (Id               => Id,
                        Identifier       => To_Unbounded_String (Identifier),
                        Name             => To_Unbounded_String (Name),
                        Description      => To_Unbounded_String (Description),
                        Unavailable_Text => To_Unbounded_String (Unavailable),
                        Icon_Name        =>
                          To_Unbounded_String
                            (Archive.Commands.To_String (Descriptor.Icon_Name)),
                        Category         => Descriptor.Category,
                        Enabled          => Descriptor.Enabled,
                        Shortcut_Present => Descriptor.Default_Shortcut.Present));
               else
                  Result.Truncated := True;
               end if;
            end if;
         end;
      end loop;
      return Result;
   end Build;
end Archive.View_Snapshots.Command_Palette;
