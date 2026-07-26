with Archive.Archives.Entries;
with Archive.Types;

package Archive.Extraction.Paths is
   type Platform_Path_Model is
     (POSIX_Path_Model,
      Windows_Path_Model,
      MacOS_Path_Model);

   type Path_Decision is
     (Path_Accepted,
      Path_Blocked_Unsafe,
      Path_Blocked_Empty,
      Path_Blocked_Unsupported_Entry);

   type Destination_Decision is
     (Destination_Accepted,
      Destination_Blocked_Empty,
      Destination_Blocked_Parent_Missing,
      Destination_Blocked_Not_Directory,
      Destination_Blocked_Inaccessible);

   type Planned_Path is record
      Decision       : Path_Decision := Path_Blocked_Unsafe;
      Safety         : Archive.Archives.Entries.Path_Safety :=
        Archive.Archives.Entries.Unsafe_Encoding;
      Relative_Key   : Archive.Types.UString;
      Component_Count : Natural := 0;
   end record;

   function Plan_Relative_Path
     (Item     : Archive.Archives.Entries.Archive_Entry;
      Platform : Platform_Path_Model := POSIX_Path_Model)
      return Planned_Path;

   function Platform_Key
     (Components : Archive.Types.String_Vectors.Vector;
      Platform   : Platform_Path_Model := POSIX_Path_Model)
      return Archive.Types.UString;

   function Validate_Destination_Root (Path : String) return Destination_Decision;
end Archive.Extraction.Paths;
