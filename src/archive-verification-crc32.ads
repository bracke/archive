with Archive.Types;
with CryptoLib.Checksums;
with Zlib;

--  CRC-32 (the standard gzip/ZIP/7z reflected polynomial) as an incremental
--  Initial/Update/Final triple. The implementation is CryptoLib.Checksums --
--  the same CRC-32 the ZIP writer already uses -- rather than a second
--  hand-rolled copy of the algorithm; this package is only the app-facing
--  adapter (it speaks Zlib.Byte_Array in and Archive.Types.CRC32_Value out).
package Archive.Verification.CRC32 is
   type CRC32_State is private;

   function Initial return CRC32_State;
   procedure Update (State : in out CRC32_State; Bytes : Zlib.Byte_Array);
   function Final (State : CRC32_State) return Archive.Types.CRC32_Value;
private
   type CRC32_State is record
      Inner : CryptoLib.Checksums.CRC32_State;
   end record;
end Archive.Verification.CRC32;
