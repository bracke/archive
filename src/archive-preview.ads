with Archive.Resource_Limits;
with Archive.Archives.Entries;
with Archive.Archives.Errors;
with Archive.Types;
with Zlib;

package Archive.Preview is
   type Preview_Kind is
     (Text_Preview,
      Hex_Preview,
      Directory_Preview,
      Link_Preview,
      Metadata_Preview,
      Image_Preview,
      Untrusted_Preview,
      Empty_Preview);

   type Preview_Result is record
      Kind      : Preview_Kind := Empty_Preview;
      Text      : Archive.Types.UString;
      Truncated : Boolean := False;
      Bytes_Used : Natural := 0;
      Trusted   : Boolean := True;
   end record;

   type Preview_Accumulator (Capacity : Natural) is limited private;

   type Preview_Limits is record
      Max_Input_Bytes : Natural :=
        Natural
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Preview_Input_Bytes));
      Max_Text_Chars  : Natural :=
        Natural
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Metadata_Bytes_Per_Entry));
      Max_Hex_Bytes   : Natural := 256;
   end record;

   procedure Initialize
     (Accumulator : in out Preview_Accumulator;
      Limits      : Preview_Limits);

   procedure Append
     (Accumulator : in out Preview_Accumulator;
      Bytes       : Zlib.Byte_Array;
      Continue    : in out Boolean);

   function Finish
     (Accumulator : Preview_Accumulator)
      return Preview_Result;

   function Bytes_Received
     (Accumulator : Preview_Accumulator)
      return Natural;

   function Limit_Reached
     (Accumulator : Preview_Accumulator)
      return Boolean;

   function Generate_Entry_From_Accumulator
     (Item        : Archive.Archives.Entries.Archive_Entry;
      Accumulator : Preview_Accumulator;
      Status      : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Integrity   : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Verified)
      return Preview_Result;
private
   type Preview_Accumulator (Capacity : Natural) is limited record
      Limits    : Preview_Limits;
      Total     : Natural := 0;
      Text_Chars : Natural := 0;
      Hex_Bytes  : Natural := 0;
      Header_Length : Natural := 0;
      All_Text  : Boolean := True;
      Hit_Limit : Boolean := False;
      Text      : Archive.Types.UString;
      Hex       : Archive.Types.UString;
      Header    : Zlib.Byte_Array (1 .. 24) := [others => 0];
   end record;
end Archive.Preview;
