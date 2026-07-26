with Ada.Calendar;
with Archive.Archives.Formats;
with Archive.Types;
with Zlib;

package Archive.Source_Monitoring is
   Max_Probe_Bytes : constant Positive := 4_096;

   type Source_Status is
     (Source_Ready,
      Source_Missing,
      Source_Not_Regular,
      Source_Read_Failed);

   type Source_Fingerprint is record
      Status        : Source_Status := Source_Missing;
      Size          : Archive.Types.Uncompressed_Size := 0;
      Modified_Time : Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
   end record;

   type Probe_Result (Length : Natural := 0) is record
      Status      : Source_Status := Source_Missing;
      Fingerprint : Source_Fingerprint;
      Bytes       : Zlib.Byte_Array (1 .. Length);
   end record;

   function Fingerprint (Path : String) return Source_Fingerprint;

   function Same_Source
     (Left  : Source_Fingerprint;
      Right : Source_Fingerprint)
      return Boolean;

   function Probe
     (Path  : String;
      Limit : Positive := Max_Probe_Bytes)
      return Probe_Result;

   function Detect_File
     (Path  : String;
      Limit : Positive := Max_Probe_Bytes)
      return Archive.Archives.Formats.Detection_Result;
end Archive.Source_Monitoring;
