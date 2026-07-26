with Ada.Containers.Vectors;

with Archive.Archives.Entries;
with Archive.Archives.Index;
with Archive.Extraction.Paths;
with Archive.Types;

package Archive.Extraction.Plans is
   type Plan_Status is
     (Plan_Ready,
      Plan_Blocked,
      Plan_Has_Conflicts);

   type Plan_Entry is record
      Source         : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Kind           : Archive.Archives.Entries.Entry_Kind :=
        Archive.Archives.Entries.Unknown;
      Path           : Archive.Extraction.Paths.Planned_Path;
      Conflict       : Boolean := False;
      Conflict_With  : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Expected_CRC32 : Archive.Types.Optional_CRC32;
   end record;

   package Plan_Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Plan_Entry);

   type Extraction_Plan is record
      Status          : Plan_Status := Plan_Ready;
      Session         : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Entries         : Plan_Entry_Vectors.Vector;
      Blocked_Count   : Natural := 0;
      Conflict_Count  : Natural := 0;
      Requested_Count : Natural := 0;
   end record;

   function Build
     (Index     : Archive.Archives.Index.Archive_Index;
      Selection : Archive.Types.Entry_Id_Vectors.Vector;
      Session   : Archive.Types.Generation_Id;
      Platform  : Archive.Extraction.Paths.Platform_Path_Model :=
        Archive.Extraction.Paths.POSIX_Path_Model)
      return Extraction_Plan;
end Archive.Extraction.Plans;
