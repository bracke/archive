with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with Archive.Archives.Entries;
with Archive.Archives.Paths;

package body Archive.Writes.Plans is
   use Ada.Strings.Unbounded;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Path_Safety;
   use type Archive.Types.Entry_Id;
   use type Archive.Types.Generation_Id;

   package Path_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Boolean,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   function Key_For
     (Path     : String;
      Platform : Archive.Extraction.Paths.Platform_Path_Model)
      return String
   is
      Norm   : constant Archive.Archives.Paths.Normalization_Result :=
        Archive.Archives.Paths.Normalize (Path);
   begin
      if Norm.Safety /= Archive.Archives.Entries.Safe_Path then
         return "";
      end if;
      return To_String (Archive.Extraction.Paths.Platform_Key (Norm.Components, Platform));
   end Key_For;

   function Existing_Path
     (Index : Archive.Archives.Index.Archive_Index;
      Key   : String;
      Platform : Archive.Extraction.Paths.Platform_Path_Model)
      return Boolean
   is
   begin
      if Key = "" then
         return False;
      end if;

      for Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
         declare
            Item : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Index, Archive.Types.Entry_Id (Id));
         begin
            if Key_For (To_String (Item.Original_Path), Platform) = Key then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Existing_Path;

   function Is_Path_Prefix (Parent, Child : String) return Boolean is
   begin
      return Parent /= ""
        and then Child'Length > Parent'Length
        and then Child (Child'First .. Child'First + Parent'Length - 1) = Parent
        and then Child (Child'First + Parent'Length) = '/';
   end Is_Path_Prefix;

   function File_Directory_Collision
     (Index    : Archive.Archives.Index.Archive_Index;
      Key      : String;
      Is_Dir   : Boolean;
      Platform : Archive.Extraction.Paths.Platform_Path_Model)
      return Boolean
   is
   begin
      if Key = "" then
         return False;
      end if;

      for Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
         declare
            Item : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Index, Archive.Types.Entry_Id (Id));
            Existing : constant String := Key_For (To_String (Item.Original_Path), Platform);
         begin
            if Existing /= "" then
               if Item.Kind /= Archive.Archives.Entries.Directory
                 and then (Is_Path_Prefix (Existing, Key) or else Is_Path_Prefix (Key, Existing))
               then
                  return True;
               end if;
            end if;
         end;
      end loop;

      return False;
   end File_Directory_Collision;

   function Pending_File_Directory_Collision
     (Targets : Path_Maps.Map;
      Key     : String;
      Is_Dir  : Boolean)
      return Boolean
   is
   begin
      for Cursor in Targets.Iterate loop
         declare
            Existing : constant String := Path_Maps.Key (Cursor);
            Existing_Is_Dir : constant Boolean := Path_Maps.Element (Cursor);
         begin
            if not Existing_Is_Dir
              and then (Is_Path_Prefix (Existing, Key) or else Is_Path_Prefix (Key, Existing))
            then
               return True;
            elsif not Is_Dir and then Is_Path_Prefix (Key, Existing) then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Pending_File_Directory_Collision;

   function Target_For (Request : Write_Request) return String is
   begin
      case Request.Action is
         when Add_File | Add_Directory | Replace_File =>
            return To_String (Request.Target_Path);
         when Rename_Entry =>
            return To_String (Request.Replacement_Path);
         when Remove_Entry =>
            return "";
      end case;
   end Target_For;

   function Needs_Existing_Entry (Action : Write_Action) return Boolean is
   begin
      return Action in Replace_File | Remove_Entry | Rename_Entry;
   end Needs_Existing_Entry;

   function Build
     (Index    : Archive.Archives.Index.Archive_Index;
      Requests : Write_Request_Vectors.Vector;
      Session  : Archive.Types.Generation_Id;
      Platform : Archive.Extraction.Paths.Platform_Path_Model :=
        Archive.Extraction.Paths.POSIX_Path_Model;
      Conflict_Action : Conflict_Resolution_Action := Resolve_Ask;
      Apply_To_All    : Boolean := False)
      return Write_Plan
   is
      Result : Write_Plan;
      Targets : Path_Maps.Map;
   begin
      Result.Session := Session;
      Result.Index := Index;
      Result.Requested_Count := Natural (Requests.Length);

      for Request of Requests loop
         declare
            Target   : constant String := Target_For (Request);
            Target_Key : constant String := Key_For (Target, Platform);
            Change   : Planned_Change :=
              (Request  => Request,
               Decision => Entry_Ready,
               Resolution => (Action => Resolve_Ask, Apply_To_All => False));
         begin
            if Session = Archive.Types.No_Generation then
               Change.Decision := Entry_Blocked_No_Session;
            elsif Needs_Existing_Entry (Request.Action)
              and then not Archive.Archives.Index.Contains (Index, Request.Source_Entry)
            then
               Change.Decision := Entry_Blocked_Missing_Entry;
            elsif Request.Action in Add_File | Add_Directory | Replace_File | Rename_Entry then
               if Target_Key = "" then
                  Change.Decision := Entry_Blocked_Unsafe_Target;
               elsif Request.Action = Replace_File then
                  if Key_For
                    (To_String
                       (Archive.Archives.Index.Entry_For
                          (Index, Request.Source_Entry).Original_Path),
                     Platform) /= Target_Key
                  then
                     Change.Decision := Entry_Blocked_Missing_Entry;
                  elsif Targets.Contains (Target_Key) then
                     Change.Decision := Entry_Conflict_Duplicate_Target;
                  else
                     Targets.Insert (Target_Key, False);
                  end if;
               elsif Targets.Contains (Target_Key) or else Existing_Path (Index, Target_Key, Platform) then
                  Change.Decision := Entry_Conflict_Duplicate_Target;
               elsif File_Directory_Collision
                 (Index, Target_Key, Request.Action = Add_Directory, Platform)
                 or else Pending_File_Directory_Collision
                   (Targets, Target_Key, Request.Action = Add_Directory)
               then
                  Change.Decision := Entry_Conflict_File_Directory;
               else
                  Targets.Insert (Target_Key, Request.Action = Add_Directory);
               end if;
            end if;

            case Change.Decision is
               when Entry_Ready =>
                  null;
               when Entry_Conflict_Duplicate_Target =>
                  Result.Conflict_Count := Result.Conflict_Count + 1;
                  Result.Duplicate_Target_Count := Result.Duplicate_Target_Count + 1;
                  Change.Resolution :=
                    (Action => Conflict_Action,
                     Apply_To_All => Apply_To_All and then Conflict_Action /= Resolve_Ask);
                  if Conflict_Action /= Resolve_Ask then
                     Result.Auto_Resolved_Count := Result.Auto_Resolved_Count + 1;
                  end if;
               when Entry_Conflict_File_Directory =>
                  Result.Conflict_Count := Result.Conflict_Count + 1;
                  Result.File_Directory_Conflict_Count :=
                    Result.File_Directory_Conflict_Count + 1;
                  Change.Resolution :=
                    (Action => Conflict_Action,
                     Apply_To_All => Apply_To_All and then Conflict_Action /= Resolve_Ask);
                  if Conflict_Action /= Resolve_Ask then
                     Result.Auto_Resolved_Count := Result.Auto_Resolved_Count + 1;
                  end if;
               when others =>
                  Result.Blocked_Count := Result.Blocked_Count + 1;
            end case;

            Result.Changes.Append (Change);
         end;
      end loop;

      if Result.Blocked_Count > 0 then
         Result.Status := Write_Plan_Blocked;
      elsif Result.Conflict_Count > Result.Auto_Resolved_Count then
         Result.Status := Write_Plan_Has_Conflicts;
      else
         Result.Status := Write_Plan_Ready;
      end if;

      return Result;
   end Build;
end Archive.Writes.Plans;
