with Archive.Archives.Readers.Dispatch;
with Zlib;

package body Archive.Verification.Entries is
   function Verify_File
     (Path        : String;
      Source_Name : String;
      Item        : Archive.Archives.Entries.Archive_Entry)
      return Entry_Verification_Result
   is
      procedure Ignore
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean) is
      begin
         pragma Unreferenced (Bytes);
         Continue := True;
      end Ignore;

      Payload : constant Archive.Archives.Readers.Dispatch.Stream_Result :=
        Archive.Archives.Readers.Dispatch.Stream_Payload_File
          (Path, Source_Name, Item, Ignore'Access);
   begin
      return (Status    => Payload.Status,
              Integrity => Payload.Integrity);
   end Verify_File;
end Archive.Verification.Entries;
