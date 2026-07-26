with Archive.Archives.Formats;
with Archive.Writes.Plans;
with Archive.Writes.Results;

package Archive.Writes.Dispatch is
   type Zip_Method is
     (Zip_Stored_Method,
      Zip_Deflate_Method,
      Zip_BZip2_Method,
      Zip_LZMA_Method,
      Zip_Zstd_Method,
      Zip_PPMd_Method);

   function Publish
     (Format           : Archive.Archives.Formats.Format_Id;
      Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Method           : Zip_Method := Zip_Deflate_Method;
      Source_Path      : String := "";
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result;

end Archive.Writes.Dispatch;
