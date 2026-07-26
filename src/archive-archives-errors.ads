package Archive.Archives.Errors is
   type Error_Code is
     (Ok,
      Read_Failed,
      Write_Failed,
      Invalid_Format,
      Unsupported_Format,
      Unsupported_Method,
      Zlib_Failed,
      Limit_Exceeded,
      Cancelled);

   type Result is record
      Code        : Error_Code := Ok;
      Message_Key : String (1 .. 64) := [others => ' '];
   end record;

   function Success return Result;
   function Failure (Code : Error_Code) return Result;
end Archive.Archives.Errors;
