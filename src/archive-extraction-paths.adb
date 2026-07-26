with Ada.Strings.Unbounded;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;

with Archive.Archives.Paths;
with Archive.Resource_Limits;

package body Archive.Extraction.Paths is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Kind;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Path_Safety;
   use type Archive.Resource_Limits.Limit_Value;

   Max_Component_Length : constant Natural := 255;

   function Join (Components : Archive.Types.String_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      for Component of Components loop
         if Length (Result) > 0 then
            Append (Result, "/");
         end if;
         Append (Result, Component);
      end loop;
      return To_String (Result);
   end Join;

   function Fold_Component (Value : String; Platform : Platform_Path_Model) return String is
      Result : Unbounded_String;
      Index  : Integer := Value'First;

      procedure Append_Lower (C : Character) is
      begin
         Append (Result, Ada.Characters.Handling.To_Lower (C));
      end Append_Lower;
   begin
      while Index <= Value'Last loop
         if Platform = MacOS_Path_Model
           and then Index + 1 <= Value'Last
           and then Character'Pos (Value (Index)) = 16#C3#
           and then Character'Pos (Value (Index + 1)) in 16#80# .. 16#85# | 16#A0# .. 16#A5#
         then
            Append (Result, "a");
            Index := Index + 2;
         elsif Platform = MacOS_Path_Model
           and then Index + 1 <= Value'Last
           and then Character'Pos (Value (Index)) = 16#C3#
           and then Character'Pos (Value (Index + 1)) in 16#88# .. 16#8B# | 16#A8# .. 16#AB#
         then
            Append (Result, "e");
            Index := Index + 2;
         elsif Platform = MacOS_Path_Model
           and then Index + 2 <= Value'Last
           and then Value (Index) in 'A' | 'a' | 'E' | 'e'
           and then Character'Pos (Value (Index + 1)) = 16#CC#
           and then Character'Pos (Value (Index + 2)) = 16#81#
         then
            Append_Lower (Value (Index));
            Index := Index + 3;
         elsif Platform = POSIX_Path_Model then
            Append (Result, Value (Index));
            Index := Index + 1;
         else
            Append_Lower (Value (Index));
            Index := Index + 1;
         end if;
      end loop;

      return To_String (Result);
   end Fold_Component;

   function Platform_Key
     (Components : Archive.Types.String_Vectors.Vector;
      Platform   : Platform_Path_Model := POSIX_Path_Model)
      return Archive.Types.UString
   is
      Result : Unbounded_String;
   begin
      for Component of Components loop
         if Length (Result) > 0 then
            Append (Result, "/");
         end if;
         Append (Result, Fold_Component (To_String (Component), Platform));
      end loop;
      return Result;
   end Platform_Key;

   function Supported_For_Extraction
     (Kind : Archive.Archives.Entries.Entry_Kind)
      return Boolean
   is
   begin
      return Kind in Archive.Archives.Entries.Regular_File | Archive.Archives.Entries.Directory;
   end Supported_For_Extraction;

   function Exceeds_Path_Limits
     (Original   : String;
      Components : Archive.Types.String_Vectors.Vector)
      return Boolean
   is
   begin
      if Archive.Resource_Limits.Limit_Value (Original'Length) >
        Archive.Resource_Limits.Default_Configured (Archive.Resource_Limits.Path_Length)
      then
         return True;
      elsif Archive.Resource_Limits.Limit_Value (Components.Length) >
        Archive.Resource_Limits.Default_Configured (Archive.Resource_Limits.Path_Component_Count)
      then
         return True;
      elsif Archive.Resource_Limits.Limit_Value (Components.Length) >
        Archive.Resource_Limits.Default_Configured (Archive.Resource_Limits.Path_Depth)
      then
         return True;
      end if;

      for Component of Components loop
         if Length (Component) > Max_Component_Length then
            return True;
         end if;
      end loop;

      return False;
   end Exceeds_Path_Limits;

   function Plan_Relative_Path
     (Item     : Archive.Archives.Entries.Archive_Entry;
      Platform : Platform_Path_Model := POSIX_Path_Model)
      return Planned_Path
   is
      Norm : constant Archive.Archives.Paths.Normalization_Result :=
        Archive.Archives.Paths.Normalize (To_String (Item.Original_Path));
      Original : constant String := To_String (Item.Original_Path);
      Result : Planned_Path;
   begin
      Result.Safety := Norm.Safety;
      Result.Component_Count := Natural (Norm.Components.Length);

      if not Supported_For_Extraction (Item.Kind) then
         Result.Decision := Path_Blocked_Unsupported_Entry;
      elsif Norm.Safety = Archive.Archives.Entries.Empty_Path then
         Result.Decision := Path_Blocked_Empty;
      elsif Norm.Safety /= Archive.Archives.Entries.Safe_Path then
         Result.Decision := Path_Blocked_Unsafe;
      elsif Exceeds_Path_Limits (Original, Norm.Components) then
         Result.Safety := Archive.Archives.Entries.Too_Long;
         Result.Decision := Path_Blocked_Unsafe;
      else
         Result.Decision := Path_Accepted;
         if Platform = POSIX_Path_Model then
            Result.Relative_Key := To_Unbounded_String (Join (Norm.Components));
         else
            Result.Relative_Key := Platform_Key (Norm.Components, Platform);
         end if;
      end if;

      return Result;
   end Plan_Relative_Path;

   function Parent_Of (Path : String) return String is
   begin
      if Path'Length = 0 then
         return "";
      end if;

      for Index in reverse Path'Range loop
         if Path (Index) = '/' then
            if Index = Path'First then
               return "/";
            end if;
            return Path (Path'First .. Index - 1);
         end if;
      end loop;

      return ".";
   end Parent_Of;

   function Validate_Destination_Root (Path : String) return Destination_Decision is
      Trimmed : constant String := Ada.Strings.Fixed.Trim (Path, Ada.Strings.Both);
      Parent  : constant String := Parent_Of (Trimmed);
   begin
      if Trimmed'Length = 0 then
         return Destination_Blocked_Empty;
      elsif Ada.Directories.Exists (Trimmed) then
         if Ada.Directories.Kind (Trimmed) = Ada.Directories.Directory then
            return Destination_Accepted;
         else
            return Destination_Blocked_Not_Directory;
         end if;
      elsif Parent = "" or else not Ada.Directories.Exists (Parent) then
         return Destination_Blocked_Parent_Missing;
      elsif Ada.Directories.Kind (Parent) /= Ada.Directories.Directory then
         return Destination_Blocked_Parent_Missing;
      else
         return Destination_Accepted;
      end if;
   exception
      when others =>
         return Destination_Blocked_Inaccessible;
   end Validate_Destination_Root;
end Archive.Extraction.Paths;
