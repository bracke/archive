package body Archive.Tasking.Cancellation is
   protected body Token is
      procedure Cancel is
      begin
         Is_Cancelled := True;
      end Cancel;

      procedure Reset is
      begin
         Is_Cancelled := False;
      end Reset;

      function Cancelled return Boolean is
      begin
         return Is_Cancelled;
      end Cancelled;
   end Token;
end Archive.Tasking.Cancellation;
