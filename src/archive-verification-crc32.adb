with CryptoLib.Checksums;
with Interfaces;

package body Archive.Verification.CRC32 is
   use type Interfaces.Unsigned_32;

   function Initial return CRC32_State is
   begin
      return (Value => 16#FFFF_FFFF#);
   end Initial;

   procedure Update (State : in out CRC32_State; Bytes : Zlib.Byte_Array) is
      C : Interfaces.Unsigned_32;
   begin
      for Byte of Bytes loop
         C := State.Value xor Interfaces.Unsigned_32 (Byte);
         for Bit in 1 .. 8 loop
            if (C and 1) = 1 then
               C := Interfaces.Shift_Right (C, 1) xor 16#EDB8_8320#;
            else
               C := Interfaces.Shift_Right (C, 1);
            end if;
         end loop;
         State.Value := C;
      end loop;
   end Update;

   function Final (State : CRC32_State) return Archive.Types.CRC32_Value is
   begin
      return Archive.Types.CRC32_Value (State.Value xor 16#FFFF_FFFF#);
   end Final;

end Archive.Verification.CRC32;
