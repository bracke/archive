package body Archive.Archives.Errors is
   function Key_For (Code : Error_Code) return String is
   begin
      case Code is
         when Ok => return "archive.ok";
         when Read_Failed => return "error.read_failed";
         when Write_Failed => return "error.write_failed";
         when Invalid_Format => return "error.invalid_format";
         when Unsupported_Format => return "error.unsupported_format";
         when Unsupported_Method => return "error.unsupported_method";
         when Zlib_Failed => return "error.zlib_failed";
         when Limit_Exceeded => return "error.limit_exceeded";
         when Cancelled => return "error.cancelled";
      end case;
   end Key_For;

   function With_Key (Code : Error_Code; Key : String) return Result is
      R : Result := (Code => Code, Message_Key => [others => ' ']);
   begin
      R.Message_Key (R.Message_Key'First .. R.Message_Key'First + Key'Length - 1) := Key;
      return R;
   end With_Key;

   function Success return Result is
   begin
      return With_Key (Ok, Key_For (Ok));
   end Success;

   function Failure (Code : Error_Code) return Result is
   begin
      return With_Key (Code, Key_For (Code));
   end Failure;
end Archive.Archives.Errors;
