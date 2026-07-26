with Archive.Archives.Entries;
with Archive.Types;

package Archive.Archives.Paths is
   type Normalization_Result is record
      Safety     : Archive.Archives.Entries.Path_Safety :=
        Archive.Archives.Entries.Safe_Path;
      Components : Archive.Types.String_Vectors.Vector;
   end record;

   function Normalize (Original : String) return Normalization_Result;
   function Safe_Display_Name (Original : String) return String;
end Archive.Archives.Paths;
