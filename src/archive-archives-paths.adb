with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body Archive.Archives.Paths is
   use Ada.Strings.Unbounded;
   use type Archive.Archives.Entries.Path_Safety;

   procedure Note
     (Result : in out Normalization_Result;
      Safety : Archive.Archives.Entries.Path_Safety)
   is
   begin
      if Result.Safety = Archive.Archives.Entries.Safe_Path then
         Result.Safety := Safety;
      end if;
   end Note;

   function Is_Reserved_Windows_Name (Value : String) return Boolean is
      Upper : String := Value;
   begin
      for C of Upper loop
         C := Ada.Characters.Handling.To_Upper (C);
      end loop;
      return Upper in "CON" | "PRN" | "AUX" | "NUL"
        or else (Upper'Length = 4 and then Upper (Upper'First .. Upper'First + 2) in "COM" | "LPT"
                 and then Upper (Upper'Last) in '1' .. '9');
   end Is_Reserved_Windows_Name;

   function Contains_Colon (Value : String) return Boolean is
   begin
      for C of Value loop
         if C = ':' then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Colon;

   function Normalize (Original : String) return Normalization_Result is
      Result : Normalization_Result;
      Start  : Positive := Original'First;
   begin
      if Original'Length = 0 then
         Note (Result, Archive.Archives.Entries.Empty_Path);
         return Result;
      end if;

      if Original (Original'First) = '/' or else Original (Original'First) = '\' then
         Note (Result, Archive.Archives.Entries.Absolute_Path);
      end if;

      if Original'Length >= 2 and then Original (Original'First + 1) = ':' then
         Note (Result, Archive.Archives.Entries.Windows_Drive_Path);
      elsif Original'Length >= 2
        and then Original (Original'First) = '\'
        and then Original (Original'First + 1) = '\'
      then
         Note (Result, Archive.Archives.Entries.Windows_UNC_Path);
      end if;

      for Index in Original'Range loop
         if Original (Index) = '/' or else Original (Index) = '\' then
            if Index > Start then
               declare
                  Part : constant String := Original (Start .. Index - 1);
               begin
                  if Part = ".." then
                     Note (Result, Archive.Archives.Entries.Parent_Traversal);
                  elsif Part /= "." then
                     if Is_Reserved_Windows_Name (Part) then
                        Note (Result, Archive.Archives.Entries.Reserved_Name);
                     elsif Contains_Colon (Part) then
                        Note (Result, Archive.Archives.Entries.Alternate_Data_Stream);
                     end if;
                     Result.Components.Append (To_Unbounded_String (Part));
                  end if;
               end;
            end if;
            Start := Index + 1;
         end if;
      end loop;

      if Start <= Original'Last then
         declare
            Part : constant String := Original (Start .. Original'Last);
         begin
            if Part = ".." then
               Note (Result, Archive.Archives.Entries.Parent_Traversal);
            elsif Part /= "." then
               if Is_Reserved_Windows_Name (Part) then
                  Note (Result, Archive.Archives.Entries.Reserved_Name);
               elsif Contains_Colon (Part) then
                  Note (Result, Archive.Archives.Entries.Alternate_Data_Stream);
               end if;
               Result.Components.Append (To_Unbounded_String (Part));
            end if;
         end;
      end if;

      if Result.Components.Is_Empty and then Result.Safety = Archive.Archives.Entries.Safe_Path then
         Note (Result, Archive.Archives.Entries.Empty_Path);
      end if;

      return Result;
   end Normalize;

   function Safe_Display_Name (Original : String) return String is
   begin
      if Original = "" then
         return "unnamed";
      end if;
      for Index in reverse Original'Range loop
         if Original (Index) = '/' or else Original (Index) = '\' then
            if Index < Original'Last then
               return Original (Index + 1 .. Original'Last);
            end if;
            return "unnamed";
         end if;
      end loop;
      return Original;
   end Safe_Display_Name;
end Archive.Archives.Paths;
