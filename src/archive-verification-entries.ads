with Archive.Archives.Entries;
with Archive.Archives.Errors;

package Archive.Verification.Entries is
   type Entry_Verification_Result is record
      Status    : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Integrity : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Not_Checked;
   end record;

   function Verify_File
     (Path        : String;
      Source_Name : String;
      Item        : Archive.Archives.Entries.Archive_Entry)
      return Entry_Verification_Result;
end Archive.Verification.Entries;
