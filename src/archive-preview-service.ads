with Archive.Tasking.Events;
with Archive.Archives.Entries;
with Archive.Archives.Errors;
with Archive.Types;
with Zlib;

package Archive.Preview.Service is
   type Preview_Service_Result is record
      Accepted : Boolean := False;
      Preview  : Archive.Preview.Preview_Result;
   end record;

   type Preview_Chunk_Consumer is access procedure
     (Bytes : Zlib.Byte_Array;
      Continue : in out Boolean);

   type Preview_Stream_Status is record
      Status    : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Integrity : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Verified;
   end record;

   type Preview_Stream_Producer is access function
     (Consumer : not null Preview_Chunk_Consumer)
      return Preview_Stream_Status;

   function Complete_Streamed_Entry
     (Item              : Archive.Archives.Entries.Archive_Entry;
      Producer          : not null Preview_Stream_Producer;
      Limits            : Archive.Preview.Preview_Limits;
      Cancelled         : Boolean;
      Event             : Archive.Tasking.Events.Event;
      Current_Session   : Archive.Types.Generation_Id;
      Current_Preview   : Archive.Types.Generation_Id)
      return Preview_Service_Result;
end Archive.Preview.Service;
