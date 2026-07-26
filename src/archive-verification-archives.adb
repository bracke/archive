with Ada.Strings.Unbounded;

with Archive.Archives.Entries;
with Archive.Verification.Entries;

package body Archive.Verification.Archives is
   use Ada.Strings.Unbounded;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Integrity_State;

   function Verify_All_File
     (Path        : String;
      Source_Name : String;
      Index       : Archive.Archives.Index.Archive_Index;
      Session     : Archive.Types.Generation_Id;
      Operation   : Archive.Types.Generation_Id)
      return Archive.Verification.Overlays.Verification_Overlay
   is
      Overlay : Archive.Verification.Overlays.Verification_Overlay :=
        Archive.Verification.Overlays.Empty
          (Session, Operation, Archive.Verification.Overlays.Verification_Completed);
   begin
      for Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
         declare
            Item : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Index, Archive.Types.Entry_Id (Id));
         begin
            if not Item.Synthetic and then Item.Kind = Archive.Archives.Entries.Regular_File then
               declare
                  Result : constant Archive.Verification.Entries.Entry_Verification_Result :=
                    Archive.Verification.Entries.Verify_File (Path, Source_Name, Item);
               begin
                  Archive.Verification.Overlays.Set_Result
                    (Overlay, Item.Id, Result.Integrity,
                     (if Result.Integrity = Archive.Archives.Entries.Verified
                      then "verification.ok"
                      elsif Result.Integrity = Archive.Archives.Entries.Failed
                      then "verification.failed"
                      else "verification.not_available"));
               end;
            end if;
         end;
      end loop;

      return Overlay;
   end Verify_All_File;
end Archive.Verification.Archives;
