with Ada.Streams;

package body Archive.Verification.CRC32 is

   function Initial return CRC32_State is
      State : CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State.Inner);
      return State;
   end Initial;

   procedure Update (State : in out CRC32_State; Bytes : Zlib.Byte_Array) is
   begin
      --  Byte at a time so an arbitrarily large chunk needs no temporary copy;
      --  CryptoLib.Checksums drives the standard reflected CRC-32 table.
      for Byte of Bytes loop
         CryptoLib.Checksums.CRC32_Update
           (State.Inner, Ada.Streams.Stream_Element (Byte));
      end loop;
   end Update;

   function Final (State : CRC32_State) return Archive.Types.CRC32_Value is
   begin
      return Archive.Types.CRC32_Value
        (CryptoLib.Checksums.CRC32_Value (State.Inner));
   end Final;

end Archive.Verification.CRC32;
