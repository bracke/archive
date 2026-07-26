with Archive.Archives.Entries;

package body Archive.View_Snapshots.Breadcrumbs is
   use type Archive.Types.Entry_Id;

   function Build
     (Index     : Archive.Archives.Index.Archive_Index;
      Directory : Archive.Types.Entry_Id)
      return Breadcrumb_Snapshot
   is
      Result : Breadcrumb_Snapshot;
      Current : Archive.Types.Entry_Id := Directory;
      Guard   : Natural := 0;
   begin
      if not Archive.Archives.Index.Contains (Index, Directory) then
         return Result;
      end if;

      while Current /= Archive.Types.No_Entry loop
         declare
            Item : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Index, Current);
         begin
            Result.Items.Prepend
              (Breadcrumb_Item'
                 (Entry_Id => Item.Id,
                  Name     => Item.Display_Name));
            Current := Item.Parent;
         end;

         Guard := Guard + 1;
         if Guard > Archive.Archives.Index.Entry_Count (Index) then
            Result.Items.Clear;
            return Result;
         end if;
      end loop;

      Result.Valid := True;
      return Result;
   end Build;
end Archive.View_Snapshots.Breadcrumbs;
