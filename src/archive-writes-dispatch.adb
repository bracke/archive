with Archive.Writes.Execution;

package body Archive.Writes.Dispatch is
   function Publish
     (Format           : Archive.Archives.Formats.Format_Id;
      Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Method           : Zip_Method := Zip_Deflate_Method;
      Source_Path      : String := "";
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      use type Archive.Archives.Formats.Format_Id;
   begin
      case Format is
         when Archive.Archives.Formats.Zip_Format =>
            if Method = Zip_Stored_Method then
               if Source_Path = "" then
                  return Archive.Writes.Execution.Publish_Zip_Stored
                    (Destination_Path, Plan,
                     Overwrite => Overwrite,
                     Cancelled => Cancelled);
               else
                  return Archive.Writes.Execution.Publish_Zip_Stored
                    (Destination_Path, Plan,
                     Source_Path => Source_Path,
                     Source_Name => Source_Name,
                     Overwrite => Overwrite,
                     Cancelled => Cancelled);
               end if;
            else
               if Source_Path = "" then
                  return Archive.Writes.Execution.Publish_Zip_Deflate
                    (Destination_Path, Plan,
                     Overwrite => Overwrite,
                     Cancelled => Cancelled);
               else
                  return Archive.Writes.Execution.Publish_Zip_Deflate
                    (Destination_Path, Plan,
                     Source_Path => Source_Path,
                     Source_Name => Source_Name,
                     Overwrite => Overwrite,
                     Cancelled => Cancelled);
               end if;
            end if;

         when Archive.Archives.Formats.Tar_Format =>
            if Source_Path = "" then
               return Archive.Writes.Execution.Publish_Tar
                 (Destination_Path, Plan,
                  Overwrite => Overwrite,
                  Cancelled => Cancelled);
            else
               return Archive.Writes.Execution.Publish_Tar
                 (Destination_Path, Plan,
                  Source_Path => Source_Path,
                  Overwrite => Overwrite,
                  Cancelled => Cancelled);
            end if;

         when Archive.Archives.Formats.Tar_GZip_Format =>
            if Source_Path = "" then
               return Archive.Writes.Execution.Publish_Tar_Gzip
                 (Destination_Path, Plan,
                  Overwrite => Overwrite,
                  Cancelled => Cancelled);
            else
               return Archive.Writes.Execution.Publish_Tar_Gzip
                 (Destination_Path, Plan,
                  Source_Path => Source_Path,
                  Overwrite => Overwrite,
                  Cancelled => Cancelled);
            end if;

         when Archive.Archives.Formats.GZip_Format =>
            return Archive.Writes.Execution.Publish_Gzip
              (Destination_Path, Plan,
               Overwrite => Overwrite,
               Cancelled => Cancelled);

         when others =>
            return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
      end case;
   end Publish;

end Archive.Writes.Dispatch;
