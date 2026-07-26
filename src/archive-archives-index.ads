with Archive.Archives.Entries;
with Archive.Types;

package Archive.Archives.Index is
   type Index_Status is
     (Complete,
      Complete_With_Warnings,
      Failed);

   type Archive_Index is private;

   type Build_Result is record
      Status : Index_Status := Complete;
      Index  : Archive_Index;
   end record;

   function Build
     (Physical : Archive.Archives.Entries.Entry_Vectors.Vector)
      return Build_Result;

   function Build_With_Limits
     (Physical      : Archive.Archives.Entries.Entry_Vectors.Vector;
      Max_Physical  : Natural;
      Max_Synthetic : Natural)
      return Build_Result;

   function Root_Id (Index : Archive_Index) return Archive.Types.Entry_Id;
   function Entry_Count (Index : Archive_Index) return Natural;
   function Physical_Count (Index : Archive_Index) return Natural;
   function Synthetic_Count (Index : Archive_Index) return Natural;
   function Contains (Index : Archive_Index; Id : Archive.Types.Entry_Id) return Boolean;

   function Entry_For
     (Index : Archive_Index;
      Id    : Archive.Types.Entry_Id)
      return Archive.Archives.Entries.Archive_Entry;

   function Children
     (Index  : Archive_Index;
      Parent : Archive.Types.Entry_Id)
      return Archive.Types.Entry_Id_Vectors.Vector;

private
   type Archive_Index is record
      Entries    : Archive.Archives.Entries.Entry_Vectors.Vector;
      Root       : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Physicals  : Natural := 0;
      Synthetics : Natural := 0;
   end record;
end Archive.Archives.Index;
