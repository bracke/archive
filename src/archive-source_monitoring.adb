with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;

package body Archive.Source_Monitoring is
   use type Ada.Calendar.Time;
   use type Ada.Directories.File_Kind;
   use type Archive.Types.Uncompressed_Size;

   function Fingerprint (Path : String) return Source_Fingerprint is
      Result : Source_Fingerprint;
   begin
      if not Ada.Directories.Exists (Path) then
         Result.Status := Source_Missing;
         return Result;
      elsif Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File then
         Result.Status := Source_Not_Regular;
         return Result;
      end if;

      Result.Status := Source_Ready;
      Result.Size := Archive.Types.Uncompressed_Size (Ada.Directories.Size (Path));
      Result.Modified_Time := Ada.Directories.Modification_Time (Path);
      return Result;
   exception
      when others =>
         return (Status => Source_Read_Failed,
                 Size => 0,
                 Modified_Time => Ada.Calendar.Time_Of (1970, 1, 1));
   end Fingerprint;

   function Same_Source
     (Left  : Source_Fingerprint;
      Right : Source_Fingerprint)
      return Boolean
   is
   begin
      return Left.Status = Right.Status
        and then Left.Size = Right.Size
        and then Left.Modified_Time = Right.Modified_Time;
   end Same_Source;

   function Probe
     (Path  : String;
      Limit : Positive := Max_Probe_Bytes)
      return Probe_Result
   is
      FP : constant Source_Fingerprint := Fingerprint (Path);
   begin
      if FP.Status /= Source_Ready then
         return (Length => 0, Status => FP.Status, Fingerprint => FP, Bytes => (1 .. 0 => 0));
      end if;

      declare
         Count : constant Natural :=
           Natural'Min (Natural'Min (Limit, Max_Probe_Bytes), Natural (FP.Size));
         File  : Ada.Streams.Stream_IO.File_Type;
         Data  : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count));
         Last  : Ada.Streams.Stream_Element_Offset := 0;
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
         if Count > 0 then
            Ada.Streams.Stream_IO.Read (File, Data, Last);
         end if;
         Ada.Streams.Stream_IO.Close (File);

         declare
            Actual : constant Natural := Natural (Last);
            Bytes  : Zlib.Byte_Array (1 .. Actual);
         begin
            for Index in Bytes'Range loop
               Bytes (Index) := Zlib.Byte (Data (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
            return (Length => Actual, Status => Source_Ready, Fingerprint => FP, Bytes => Bytes);
         end;
      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
            return
              (Length => 0,
               Status => Source_Read_Failed,
               Fingerprint => (Status => Source_Read_Failed,
                               Size => 0,
                               Modified_Time => Ada.Calendar.Time_Of (1970, 1, 1)),
               Bytes => (1 .. 0 => 0));
      end;
   end Probe;

   function Detect_File
     (Path  : String;
      Limit : Positive := Max_Probe_Bytes)
      return Archive.Archives.Formats.Detection_Result
   is
      P : constant Probe_Result := Probe (Path, Limit);
   begin
      if P.Status /= Source_Ready then
         return (Status => Archive.Archives.Formats.Read_Failed,
                 Format => Archive.Archives.Formats.Unknown_Format);
      end if;
      return Archive.Archives.Formats.Detect_File (Path, Limit);
   end Detect_File;
end Archive.Source_Monitoring;
