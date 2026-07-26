with Archive.Archives.Index;
with Archive.Verification.Overlays;
with Archive.Types;

package Archive.Verification.Archives is
   function Verify_All_File
     (Path        : String;
      Source_Name : String;
      Index       : Archive.Archives.Index.Archive_Index;
      Session     : Archive.Types.Generation_Id;
      Operation   : Archive.Types.Generation_Id)
      return Archive.Verification.Overlays.Verification_Overlay;
end Archive.Verification.Archives;
