with Archive.Types;
with Interfaces;
with Zlib;

package Archive.Verification.CRC32 is
   type CRC32_State is private;

   function Initial return CRC32_State;
   procedure Update (State : in out CRC32_State; Bytes : Zlib.Byte_Array);
   function Final (State : CRC32_State) return Archive.Types.CRC32_Value;
private
   type CRC32_State is record
      Value : Interfaces.Unsigned_32 := 16#FFFF_FFFF#;
   end record;
end Archive.Verification.CRC32;
