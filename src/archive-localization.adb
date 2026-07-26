with Ada.Containers.Vectors;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Messages.Arguments;
with Messages.Result;
with Messages.Runtime;

package body Archive.Localization is
   use Ada.Strings.Unbounded;
   use type Messages.Result.Render_Status;

   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Unbounded_String);

   Runtime        : Messages.Runtime.Instance;
   Initialized    : Boolean := False;
   Available      : Boolean := False;
   Loaded_Locales : String_Vectors.Vector;

   function Environment_Locale (Name : String) return String;
   function Catalog_Root return String;
   function Catalog_Path return String;
   function Locale_Catalog_Path (Locale : String) return String;
   function Locale_Loaded (Locale : String) return Boolean;
   procedure Load_Locale (Locale : String);
   procedure Ensure_Initialized;
   function Render_Text (Key : String; Locale : String) return String;

   function Normalize_Locale (Value : String) return String is
      Raw    : constant String := Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both);
      Last   : Natural := Raw'Last;
      Result : Unbounded_String;
      Region : Boolean := False;
   begin
      if Raw'Length = 0 then
         return "en";
      end if;

      for Index in Raw'Range loop
         if Raw (Index) = '.' or else Raw (Index) = '@' then
            Last := Index - 1;
            exit;
         end if;
      end loop;

      if Last < Raw'First then
         return "en";
      end if;

      declare
         Base : constant String := Raw (Raw'First .. Last);
      begin
         if Base = "C" or else Base = "POSIX" then
            return "en";
         end if;

         for Character of Base loop
            if Character = '_' or else Character = '-' then
               Append (Result, '-');
               Region := True;
            elsif Region then
               Append (Result, Ada.Characters.Handling.To_Upper (Character));
            else
               Append (Result, Ada.Characters.Handling.To_Lower (Character));
            end if;
         end loop;
      end;

      if Length (Result) = 0 then
         return "en";
      end if;

      return To_String (Result);
   end Normalize_Locale;

   function System_Locale return String is
      LC_All      : constant String := Environment_Locale ("LC_ALL");
      LC_Messages : constant String := Environment_Locale ("LC_MESSAGES");
      Lang        : constant String := Environment_Locale ("LANG");
   begin
      if LC_All /= "" then
         return LC_All;
      elsif LC_Messages /= "" then
         return LC_Messages;
      elsif Lang /= "" then
         return Lang;
      end if;

      return "en";
   end System_Locale;

   function Environment_Locale (Name : String) return String is
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return "";
      end if;

      declare
         Value : constant String :=
           Ada.Strings.Fixed.Trim
             (Ada.Environment_Variables.Value (Name), Ada.Strings.Both);
      begin
         if Value'Length = 0 then
            return "";
         end if;

         return Normalize_Locale (Value);
      end;
   end Environment_Locale;

   function Catalog_Root return String is
   begin
      if Ada.Directories.Exists ("share/archive.catalog") then
         return "share";
      elsif Ada.Directories.Exists ("../../share/archive.catalog") then
         return "../../share";
      elsif Ada.Directories.Exists ("../share/archive.catalog") then
         return "../share";
      end if;

      return "share";
   end Catalog_Root;

   function Catalog_Path return String is
   begin
      return Catalog_Root & "/archive.catalog";
   end Catalog_Path;

   function Locale_Catalog_Path (Locale : String) return String is
   begin
      return Catalog_Root & "/locales/archive-" & Locale & ".catalog";
   end Locale_Catalog_Path;

   function Locale_Loaded (Locale : String) return Boolean is
   begin
      for Item of Loaded_Locales loop
         if To_String (Item) = Locale then
            return True;
         end if;
      end loop;

      return False;
   end Locale_Loaded;

   procedure Load_Locale (Locale : String) is
      Normalized : constant String := Normalize_Locale (Locale);
      Path       : constant String := Locale_Catalog_Path (Normalized);
   begin
      if not Available or else Locale_Loaded (Normalized) then
         return;
      end if;

      if Ada.Directories.Exists (Path) then
         Messages.Runtime.Load (Runtime, Path);
         Available := Messages.Runtime.Is_Valid (Runtime);
      end if;

      Loaded_Locales.Append (To_Unbounded_String (Normalized));

      for Index in Normalized'Range loop
         if Normalized (Index) = '-' then
            Load_Locale (Normalized (Normalized'First .. Index - 1));
            exit;
         end if;
      end loop;
   end Load_Locale;

   procedure Ensure_Initialized is
   begin
      if not Initialized then
         Messages.Runtime.Initialize (Runtime, Catalog_Path);
         Available := Messages.Runtime.Is_Valid (Runtime);
         Initialized := True;
         Load_Locale (System_Locale);
      end if;
   end Ensure_Initialized;

   function Text (Key : String; Locale : String := "") return String is
      Effective_Locale : constant String :=
        (if Locale'Length = 0 then System_Locale else Normalize_Locale (Locale));
   begin
      Ensure_Initialized;
      Load_Locale (Effective_Locale);

      declare
         Rendered : constant String := Render_Text (Key, Effective_Locale);
      begin
         for Index in Effective_Locale'Range loop
            if Effective_Locale (Index) = '-' then
               declare
                  Language : constant String :=
                    Effective_Locale (Effective_Locale'First .. Index - 1);
                  Default_Rendered : constant String := Render_Text (Key, "en");
                  Language_Rendered : constant String := Render_Text (Key, Language);
               begin
                  if Language_Rendered /= Key
                    and then Language_Rendered /= Default_Rendered
                    and then (Rendered = Key or else Rendered = Default_Rendered)
                  then
                     return Language_Rendered;
                  end if;
               end;

               exit;
            end if;
         end loop;

         if Rendered /= Key then
            return Rendered;
         end if;
      end;

      for Index in Effective_Locale'Range loop
         if Effective_Locale (Index) = '-' then
            declare
               Language_Rendered : constant String :=
                 Render_Text (Key, Effective_Locale (Effective_Locale'First .. Index - 1));
            begin
               if Language_Rendered /= Key then
                  return Language_Rendered;
               end if;
            end;

            exit;
         end if;
      end loop;

      return Key;
   end Text;

   function Render_Text (Key : String; Locale : String) return String is
      Args   : Messages.Arguments.Arguments;
      Result : Messages.Result.Render_Result;
   begin
      Ensure_Initialized;

      if not Available then
         return Key;
      end if;

      Result :=
        Messages.Runtime.Render
          (Item      => Runtime,
           Locale    => Locale,
           Key       => Key,
           Arguments => Args);

      if Result.Status = Messages.Result.Success then
         return Messages.Result.Output_Text (Result.Text);
      end if;

      return Key;
   end Render_Text;
end Archive.Localization;
