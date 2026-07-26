with Ada.Directories;
with Ada.Text_IO;
with Ada.Strings.Unbounded;

package body Archive.Settings is
   use Ada.Strings.Unbounded;

   function Default_Settings return Settings_Model is
      Result : Settings_Model;
   begin
      Result.Locale_Mode := To_Unbounded_String ("system");
      Result.Explicit_Locale := To_Unbounded_String ("en");
      Result.Details_Columns := Archive.View_Snapshots.Columns.Default_Columns;
      return Result;
   end Default_Settings;

   function Clamp_Preview_Limit (Value : Natural) return Natural is
   begin
      if Value > Hard_Max_Preview_Bytes then
         return Hard_Max_Preview_Bytes;
      elsif Value = 0 then
         return 1;
      else
         return Value;
      end if;
   end Clamp_Preview_Limit;

   function Validate_Extraction_Limit
     (Id    : Archive.Resource_Limits.Limit_Id;
      Value : Archive.Resource_Limits.Limit_Value)
      return Archive.Resource_Limits.Limit_Value
   is
      Result : constant Archive.Resource_Limits.Validation_Result :=
        Archive.Resource_Limits.Validate (Id, Value);
   begin
      return Result.Effective;
   end Validate_Extraction_Limit;

   function Bool_Token (Value : Boolean) return String is
   begin
      if Value then
         return "true";
      else
         return "false";
      end if;
   end Bool_Token;

   function Natural_Token (Value : Natural) return String is
      Raw : constant String := Natural'Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Natural_Token;

   function Parse_Bool (Token : String; Success : out Boolean) return Boolean is
   begin
      if Token = "true" then
         Success := True;
         return True;
      elsif Token = "false" then
         Success := True;
         return False;
      else
         Success := False;
         return False;
      end if;
   end Parse_Bool;

   function View_Mode_Token (Mode : Archive.Types.View_Mode) return String is
   begin
      case Mode is
         when Archive.Types.Grid_View =>
            return "grid";
         when Archive.Types.Compact_View =>
            return "compact";
         when Archive.Types.Details_View =>
            return "details";
      end case;
   end View_Mode_Token;

   function Parse_View_Mode (Token : String; Success : out Boolean) return Archive.Types.View_Mode is
   begin
      if Token = "grid" then
         Success := True;
         return Archive.Types.Grid_View;
      elsif Token = "compact" then
         Success := True;
         return Archive.Types.Compact_View;
      elsif Token = "details" then
         Success := True;
         return Archive.Types.Details_View;
      else
         Success := False;
         return Archive.Types.Grid_View;
      end if;
   end Parse_View_Mode;

   function Conflict_Policy_Token (Policy : Extraction_Conflict_Policy) return String is
   begin
      case Policy is
         when Ask => return "ask";
         when Skip => return "skip";
         when Overwrite => return "overwrite";
         when Rename => return "rename";
      end case;
   end Conflict_Policy_Token;

   function Parse_Conflict_Policy
     (Token   : String;
      Success : out Boolean)
      return Extraction_Conflict_Policy
   is
   begin
      if Token = "ask" then
         Success := True;
         return Ask;
      elsif Token = "skip" then
         Success := True;
         return Skip;
      elsif Token = "overwrite" then
         Success := True;
         return Overwrite;
      elsif Token = "rename" then
         Success := True;
         return Rename;
      else
         Success := False;
         return Ask;
      end if;
   end Parse_Conflict_Policy;

   function Link_Policy_Token (Policy : Link_Extraction_Policy) return String is
   begin
      case Policy is
         when Skip_Links => return "skip";
         when Safe_Internal_Links => return "safe-internal";
      end case;
   end Link_Policy_Token;

   function Parse_Link_Policy
     (Token   : String;
      Success : out Boolean)
      return Link_Extraction_Policy
   is
   begin
      if Token = "skip" then
         Success := True;
         return Skip_Links;
      elsif Token = "safe-internal" then
         Success := True;
         return Safe_Internal_Links;
      else
         Success := False;
         return Skip_Links;
      end if;
   end Parse_Link_Policy;

   function Column_Tokens
     (Columns : Archive.View_Snapshots.Columns.Column_Vectors.Vector)
      return String
   is
      Result : Unbounded_String;
      First  : Boolean := True;
   begin
      for Id of Columns loop
         if First then
            First := False;
         else
            Append (Result, ",");
         end if;
         Append (Result, Archive.View_Snapshots.Columns.Token (Id));
      end loop;
      return To_String (Result);
   end Column_Tokens;

   function Recent_Tokens
     (Recent : Archive.Types.String_Vectors.Vector)
      return String
   is
      Result : Unbounded_String;
      First  : Boolean := True;
   begin
      for Path of Recent loop
         if First then
            First := False;
         else
            Append (Result, "|");
         end if;
         Append (Result, To_String (Path));
      end loop;
      return To_String (Result);
   end Recent_Tokens;

   procedure Remember_Recent_Archive
     (Settings : in out Settings_Model;
      Path     : String)
   is
      Existing : Natural := 0;
   begin
      if Path = "" then
         return;
      end if;

      if not Settings.Recent_Archives.Is_Empty then
         for Index in Settings.Recent_Archives.First_Index
           .. Settings.Recent_Archives.Last_Index
         loop
            if To_String (Settings.Recent_Archives.Element (Index)) = Path then
               Existing := Natural (Index);
               exit;
            end if;
         end loop;
      end if;

      if Existing > 0 then
         Settings.Recent_Archives.Delete (Positive (Existing));
      end if;

      Settings.Recent_Archives.Prepend (To_Unbounded_String (Path));
      while Natural (Settings.Recent_Archives.Length) > Max_Recent_Items loop
         Settings.Recent_Archives.Delete_Last;
      end loop;
   end Remember_Recent_Archive;

   procedure Parse_Recent
     (Value    : String;
      Settings : in out Settings_Model)
   is
      Start : Natural := Value'First;

      procedure Append_Parsed (Path : String) is
         Existing : Boolean := False;
      begin
         if Path = ""
           or else Natural (Settings.Recent_Archives.Length) >= Max_Recent_Items
         then
            return;
         end if;

         if not Settings.Recent_Archives.Is_Empty then
            for Stored of Settings.Recent_Archives loop
               if To_String (Stored) = Path then
                  Existing := True;
                  exit;
               end if;
            end loop;
         end if;

         if not Existing then
            Settings.Recent_Archives.Append (To_Unbounded_String (Path));
         end if;
      end Append_Parsed;
   begin
      Settings.Recent_Archives.Clear;
      if Value'Length = 0 then
         return;
      end if;

      for Index in Value'Range loop
         if Value (Index) = '|' then
            if Start <= Index - 1 then
               Append_Parsed (Value (Start .. Index - 1));
            end if;
            Start := Index + 1;
         end if;
      end loop;

      if Start <= Value'Last then
         Append_Parsed (Value (Start .. Value'Last));
      end if;
   end Parse_Recent;

   procedure Parse_Columns
     (Value    : String;
      Columns  : in out Archive.View_Snapshots.Columns.Column_Vectors.Vector;
      Valid    : in out Boolean)
   is
      Start : Natural := Value'First;
   begin
      Columns.Clear;
      if Value'Length = 0 then
         Valid := False;
         Columns := Archive.View_Snapshots.Columns.Default_Columns;
         return;
      end if;

      for Index in Value'Range loop
         if Value (Index) = ',' then
            declare
               Token : constant String := Value (Start .. Index - 1);
            begin
               if Archive.View_Snapshots.Columns.Contains (Token) then
                  Columns.Append (Archive.View_Snapshots.Columns.Id_For_Token (Token));
               else
                  Valid := False;
               end if;
            end;
            Start := Index + 1;
         end if;
      end loop;

      if Start <= Value'Last then
         declare
            Token : constant String := Value (Start .. Value'Last);
         begin
            if Archive.View_Snapshots.Columns.Contains (Token) then
               Columns.Append (Archive.View_Snapshots.Columns.Id_For_Token (Token));
            else
               Valid := False;
            end if;
         end;
      else
         Valid := False;
      end if;

      if Natural (Columns.Length) = 0 then
         Columns := Archive.View_Snapshots.Columns.Default_Columns;
      end if;
   end Parse_Columns;

   function Serialize (Settings : Settings_Model) return String is
   begin
      return "schema=" & Natural_Token (Current_Schema) & ASCII.LF
        & "locale_mode=" & To_String (Settings.Locale_Mode) & ASCII.LF
        & "explicit_locale=" & To_String (Settings.Explicit_Locale) & ASCII.LF
        & "default_view=" & View_Mode_Token (Settings.Default_View) & ASCII.LF
        & "details_columns=" & Column_Tokens (Settings.Details_Columns) & ASCII.LF
        & "directories_first=" & Bool_Token (Settings.Directories_First) & ASCII.LF
        & "preview_visible=" & Bool_Token (Settings.Preview_Visible) & ASCII.LF
        & "preview_byte_limit=" & Natural_Token (Settings.Preview_Byte_Limit) & ASCII.LF
        & "per_entry_extraction_limit="
        & Archive.Resource_Limits.Limit_Value'Image
            (Settings.Per_Entry_Extraction_Limit) & ASCII.LF
        & "total_extraction_limit="
        & Archive.Resource_Limits.Limit_Value'Image
            (Settings.Total_Extraction_Limit) & ASCII.LF
        & "conflict_policy=" & Conflict_Policy_Token (Settings.Conflict_Policy) & ASCII.LF
        & "write_conflict_policy=" & Conflict_Policy_Token (Settings.Write_Conflict_Policy) & ASCII.LF
        & "link_policy=" & Link_Policy_Token (Settings.Link_Policy) & ASCII.LF
        & "show_unsafe_entries=" & Bool_Token (Settings.Show_Unsafe_Entries) & ASCII.LF
        & "startup_reopen_recent=" & Bool_Token (Settings.Startup_Reopen_Recent) & ASCII.LF
        & "window_width=" & Natural_Token (Settings.Window_Width) & ASCII.LF
        & "window_height=" & Natural_Token (Settings.Window_Height) & ASCII.LF
        & "window_maximized=" & Bool_Token (Settings.Window_Maximized) & ASCII.LF
        & "toolbar_visible=" & Bool_Token (Settings.Toolbar_Visible) & ASCII.LF
        & "status_bar_visible=" & Bool_Token (Settings.Status_Bar_Visible) & ASCII.LF
        & "recent_archives=" & Recent_Tokens (Settings.Recent_Archives) & ASCII.LF;
   end Serialize;

   procedure Apply
     (Settings : in out Settings_Model;
      Key      : String;
      Value    : String;
      Valid    : in out Boolean)
   is
      OK : Boolean := False;
   begin
      if Key = "schema" then
         begin
            if Natural'Value (Value) not in 0 .. Current_Schema then
               Valid := False;
            end if;
         exception
            when others =>
               Valid := False;
         end;
      elsif Key = "locale_mode" then
         Settings.Locale_Mode := To_Unbounded_String (Value);
      elsif Key = "explicit_locale" then
         Settings.Explicit_Locale := To_Unbounded_String (Value);
      elsif Key = "default_view" then
         Settings.Default_View := Parse_View_Mode (Value, OK);
         Valid := Valid and OK;
      elsif Key = "details_columns" then
         Parse_Columns (Value, Settings.Details_Columns, Valid);
      elsif Key = "directories_first" then
         Settings.Directories_First := Parse_Bool (Value, OK);
         Valid := Valid and OK;
      elsif Key = "preview_visible" then
         Settings.Preview_Visible := Parse_Bool (Value, OK);
         Valid := Valid and OK;
      elsif Key = "preview_byte_limit" then
         begin
            Settings.Preview_Byte_Limit := Clamp_Preview_Limit (Natural'Value (Value));
         exception
            when others =>
               Valid := False;
         end;
      elsif Key = "per_entry_extraction_limit" then
         begin
            Settings.Per_Entry_Extraction_Limit :=
              Validate_Extraction_Limit
                (Archive.Resource_Limits.Per_Entry_Extraction_Output,
                 Archive.Resource_Limits.Limit_Value'Value (Value));
         exception
            when others =>
               Valid := False;
         end;
      elsif Key = "total_extraction_limit" then
         begin
            Settings.Total_Extraction_Limit :=
              Validate_Extraction_Limit
                (Archive.Resource_Limits.Total_Extraction_Output,
                 Archive.Resource_Limits.Limit_Value'Value (Value));
         exception
            when others =>
               Valid := False;
         end;
      elsif Key = "conflict_policy" then
         Settings.Conflict_Policy := Parse_Conflict_Policy (Value, OK);
         Valid := Valid and OK;
      elsif Key = "write_conflict_policy" then
         Settings.Write_Conflict_Policy := Parse_Conflict_Policy (Value, OK);
         Valid := Valid and OK;
      elsif Key = "link_policy" then
         Settings.Link_Policy := Parse_Link_Policy (Value, OK);
         Valid := Valid and OK;
      elsif Key = "show_unsafe_entries" then
         Settings.Show_Unsafe_Entries := Parse_Bool (Value, OK);
         Valid := Valid and OK;
      elsif Key = "startup_reopen_recent" then
         Settings.Startup_Reopen_Recent := Parse_Bool (Value, OK);
         Valid := Valid and OK;
      elsif Key = "window_width" then
         begin
            Settings.Window_Width := Natural'Value (Value);
         exception
            when others =>
               Valid := False;
         end;
      elsif Key = "window_height" then
         begin
            Settings.Window_Height := Natural'Value (Value);
         exception
            when others =>
               Valid := False;
         end;
      elsif Key = "window_maximized" then
         Settings.Window_Maximized := Parse_Bool (Value, OK);
         Valid := Valid and OK;
      elsif Key = "toolbar_visible" then
         Settings.Toolbar_Visible := Parse_Bool (Value, OK);
         Valid := Valid and OK;
      elsif Key = "status_bar_visible" then
         Settings.Status_Bar_Visible := Parse_Bool (Value, OK);
         Valid := Valid and OK;
      elsif Key = "recent_archives" then
         Parse_Recent (Value, Settings);
      elsif Key /= "" then
         null;
      end if;
   end Apply;

   function Parse (Text : String) return Settings_Parse_Result is
      Result : Settings_Parse_Result :=
        (Success => True,
         Settings => Default_Settings,
         Error_Key => Null_Unbounded_String);
      Line_Start : Natural := Text'First;
      Valid : Boolean := True;
      Seen_Schema : Boolean := False;
      Schema      : Natural := 0;
   begin
      if Text'Length = 0 then
         return Result;
      end if;

      for Index in Text'Range loop
         if Text (Index) = ASCII.LF then
            declare
               Line : constant String := Text (Line_Start .. Index - 1);
               Equal : Natural := 0;
            begin
               for Pos in Line'Range loop
                  if Line (Pos) = '=' then
                     Equal := Pos;
                     exit;
                  end if;
               end loop;
               if Equal > 0 then
                  if Line (Line'First .. Equal - 1) = "schema" then
                     Seen_Schema := True;
                     begin
                        Schema := Natural'Value (Line (Equal + 1 .. Line'Last));
                     exception
                        when others =>
                           Valid := False;
                     end;
                  end if;
                  Apply
                    (Result.Settings,
                     Line (Line'First .. Equal - 1),
                     Line (Equal + 1 .. Line'Last),
                     Valid);
               elsif Line /= "" then
                  Valid := False;
               end if;
            end;
            Line_Start := Index + 1;
         end if;
      end loop;

      if Line_Start <= Text'Last then
         declare
            Line : constant String := Text (Line_Start .. Text'Last);
            Equal : Natural := 0;
         begin
            for Pos in Line'Range loop
               if Line (Pos) = '=' then
                  Equal := Pos;
                  exit;
               end if;
            end loop;
            if Equal > 0 then
               if Line (Line'First .. Equal - 1) = "schema" then
                  Seen_Schema := True;
                  begin
                     Schema := Natural'Value (Line (Equal + 1 .. Line'Last));
                  exception
                     when others =>
                        Valid := False;
                  end;
               end if;
               Apply
                 (Result.Settings,
                  Line (Line'First .. Equal - 1),
                  Line (Equal + 1 .. Line'Last),
                  Valid);
            elsif Line /= "" then
               Valid := False;
            end if;
         end;
      end if;

      if not Seen_Schema then
         Schema := 0;
      end if;

      if Schema > Current_Schema then
         Valid := False;
      end if;

      if not Valid then
         Result.Success := False;
         Result.Error_Key := To_Unbounded_String ("settings.invalid");
      end if;

      return Result;
   end Parse;

   function Quarantine_Path (Path : String) return String is
   begin
      return Path & ".invalid";
   end Quarantine_Path;

   function Read_File (Path : String) return String is
      File   : Ada.Text_IO.File_Type;
      Result : Unbounded_String;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Result, Ada.Text_IO.Get_Line (File));
         Append (Result, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (File);
      return To_String (Result);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Read_File;

   function Load (Path : String) return Settings_Parse_Result is
   begin
      if not Ada.Directories.Exists (Path) then
         return (Success => True, Settings => Default_Settings, Error_Key => Null_Unbounded_String);
      end if;
      declare
         Result : Settings_Parse_Result := Parse (Read_File (Path));
      begin
         if not Result.Success then
            declare
               Quarantine : constant String := Quarantine_Path (Path);
            begin
               if Ada.Directories.Exists (Quarantine) then
                  Ada.Directories.Delete_File (Quarantine);
               end if;
               Ada.Directories.Rename (Path, Quarantine);
            exception
               when others =>
                  null;
            end;
            Result.Settings := Default_Settings;
         end if;
         return Result;
      end;
   exception
      when others =>
         return
           (Success => False,
            Settings => Default_Settings,
            Error_Key => To_Unbounded_String ("settings.read_failed"));
   end Load;

   function Save (Path : String; Settings : Settings_Model) return Settings_Write_Result is
      Temp : constant String := Path & ".tmp";
      Backup : constant String := Path & ".bak";
      File : Ada.Text_IO.File_Type;
      Had_Original : Boolean := False;
   begin
      declare
         Parent : constant String := Ada.Directories.Containing_Directory (Path);
      begin
         if Parent /= "" and then not Ada.Directories.Exists (Parent) then
            Ada.Directories.Create_Path (Parent);
         end if;
      exception
         when others =>
            null;
      end;

      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Temp);
      Ada.Text_IO.Put (File, Serialize (Settings));
      Ada.Text_IO.Close (File);

      if Ada.Directories.Exists (Backup) then
         Ada.Directories.Delete_File (Backup);
      end if;
      if Ada.Directories.Exists (Path) then
         Had_Original := True;
         Ada.Directories.Rename (Path, Backup);
      end if;
      Ada.Directories.Rename (Temp, Path);
      if Had_Original and then Ada.Directories.Exists (Backup) then
         Ada.Directories.Delete_File (Backup);
      end if;
      return (Success => True, Error_Key => Null_Unbounded_String);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         if Had_Original and then Ada.Directories.Exists (Backup)
           and then not Ada.Directories.Exists (Path)
         then
            begin
               Ada.Directories.Rename (Backup, Path);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Success => False, Error_Key => To_Unbounded_String ("settings.write_failed"));
   end Save;
end Archive.Settings;
