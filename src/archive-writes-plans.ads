with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Archive.Archives.Index;
with Archive.Extraction.Paths;
with Archive.Types;

package Archive.Writes.Plans is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   type Write_Action is
     (Add_File,
      Add_Directory,
      Replace_File,
      Remove_Entry,
      Rename_Entry);

   type Plan_Status is
     (Write_Plan_Ready,
      Write_Plan_Blocked,
      Write_Plan_Has_Conflicts);

   type Entry_Decision is
     (Entry_Ready,
      Entry_Blocked_No_Session,
      Entry_Blocked_Missing_Entry,
      Entry_Blocked_Unsafe_Target,
      Entry_Conflict_Duplicate_Target,
      Entry_Conflict_File_Directory);

   type Conflict_Resolution_Action is
     (Resolve_Ask,
      Resolve_Skip,
      Resolve_Overwrite,
      Resolve_Rename);

   type Conflict_Resolution is record
      Action       : Conflict_Resolution_Action := Resolve_Ask;
      Apply_To_All : Boolean := False;
   end record;

   type Write_Request is record
      Action          : Write_Action := Add_File;
      Source_Entry    : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Host_Source     : UString;
      Target_Path     : UString;
      Replacement_Path : UString;
   end record;

   package Write_Request_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Write_Request);

   type Planned_Change is record
      Request  : Write_Request;
      Decision : Entry_Decision := Entry_Ready;
      Resolution : Conflict_Resolution;
   end record;

   package Planned_Change_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Planned_Change);

   type Write_Plan is record
      Status          : Plan_Status := Write_Plan_Ready;
      Session         : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Index           : Archive.Archives.Index.Archive_Index;
      Changes         : Planned_Change_Vectors.Vector;
      Requested_Count : Natural := 0;
      Blocked_Count   : Natural := 0;
      Conflict_Count  : Natural := 0;
      Duplicate_Target_Count : Natural := 0;
      File_Directory_Conflict_Count : Natural := 0;
      Auto_Resolved_Count : Natural := 0;
   end record;

   function Build
     (Index    : Archive.Archives.Index.Archive_Index;
      Requests : Write_Request_Vectors.Vector;
      Session  : Archive.Types.Generation_Id;
      Platform : Archive.Extraction.Paths.Platform_Path_Model :=
        Archive.Extraction.Paths.POSIX_Path_Model;
      Conflict_Action : Conflict_Resolution_Action := Resolve_Ask;
      Apply_To_All    : Boolean := False)
      return Write_Plan;
end Archive.Writes.Plans;
