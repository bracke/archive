package Archive.Tasking.Cancellation is
   protected type Token is
      procedure Cancel;
      procedure Reset;
      function Cancelled return Boolean;
   private
      Is_Cancelled : Boolean := False;
   end Token;
end Archive.Tasking.Cancellation;
