with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

package body Archive.Extraction.Plans is
   use Ada.Strings.Unbounded;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Extraction.Paths.Path_Decision;
   use type Archive.Types.Entry_Id;

   package Path_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Archive.Types.Entry_Id,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   function Build
     (Index     : Archive.Archives.Index.Archive_Index;
      Selection : Archive.Types.Entry_Id_Vectors.Vector;
      Session   : Archive.Types.Generation_Id;
      Platform  : Archive.Extraction.Paths.Platform_Path_Model :=
        Archive.Extraction.Paths.POSIX_Path_Model)
      return Extraction_Plan
   is
      Result : Extraction_Plan;
      Seen   : Path_Maps.Map;
      Expanded : Archive.Types.Entry_Id_Vectors.Vector;

      function Already_Expanded (Id : Archive.Types.Entry_Id) return Boolean is
      begin
         for Existing of Expanded loop
            if Existing = Id then
               return True;
            end if;
         end loop;
         return False;
      end Already_Expanded;

      procedure Append_With_Descendants (Id : Archive.Types.Entry_Id) is
      begin
         if Already_Expanded (Id) then
            return;
         end if;

         Expanded.Append (Id);

         if Archive.Archives.Index.Contains (Index, Id)
           and then Archive.Archives.Index.Entry_For (Index, Id).Kind =
             Archive.Archives.Entries.Directory
         then
            declare
               Child_Ids : constant Archive.Types.Entry_Id_Vectors.Vector :=
                 Archive.Archives.Index.Children (Index, Id);
            begin
               for Child_Id of Child_Ids loop
                  Append_With_Descendants (Child_Id);
               end loop;
            end;
         end if;
      end Append_With_Descendants;
   begin
      Result.Session := Session;
      Result.Requested_Count := Natural (Selection.Length);

      for Id of Selection loop
         Append_With_Descendants (Id);
      end loop;

      for Id of Expanded loop
         if Archive.Archives.Index.Contains (Index, Id) then
            declare
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Index, Id);
               Planned : constant Archive.Extraction.Paths.Planned_Path :=
                 Archive.Extraction.Paths.Plan_Relative_Path (Item, Platform);
               Out_Entry : Plan_Entry :=
                 (Source         => Id,
                  Kind           => Item.Kind,
                  Path           => Planned,
                  Conflict       => False,
                  Conflict_With  => Archive.Types.No_Entry,
                  Expected_CRC32 => Item.CRC32);
               Key : constant String := To_String (Planned.Relative_Key);
            begin
               if Planned.Decision /= Archive.Extraction.Paths.Path_Accepted then
                  Result.Blocked_Count := Result.Blocked_Count + 1;
               elsif Seen.Contains (Key) then
                  Out_Entry.Conflict := True;
                  Out_Entry.Conflict_With := Seen.Element (Key);
                  Result.Conflict_Count := Result.Conflict_Count + 1;
               else
                  Seen.Insert (Key, Id);
               end if;
               Result.Entries.Append (Out_Entry);
            end;
         else
            Result.Blocked_Count := Result.Blocked_Count + 1;
            Result.Entries.Append
              (Plan_Entry'
                 (Source => Id,
                  Kind => Archive.Archives.Entries.Unknown,
                  Path => (Decision => Archive.Extraction.Paths.Path_Blocked_Unsupported_Entry,
                           Safety => Archive.Archives.Entries.Unsafe_Encoding,
                           Relative_Key => Null_Unbounded_String,
                           Component_Count => 0),
                  Conflict => False,
                  Conflict_With => Archive.Types.No_Entry,
                  Expected_CRC32 => (Present => False)));
         end if;
      end loop;

      if Result.Blocked_Count > 0 then
         Result.Status := Plan_Blocked;
      elsif Result.Conflict_Count > 0 then
         Result.Status := Plan_Has_Conflicts;
      else
         Result.Status := Plan_Ready;
      end if;

      return Result;
   end Build;
end Archive.Extraction.Plans;
