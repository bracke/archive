with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

with Archive.Archives.Paths;
with Archive.Resource_Limits;

package body Archive.Archives.Index is
   use Ada.Strings.Unbounded;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Path_Safety;
   use type Archive.Types.Entry_Id;

   package Path_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Archive.Types.Entry_Id,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   function Next_Id (Index : Archive_Index) return Archive.Types.Entry_Id is
   begin
      return Archive.Types.Entry_Id (Index.Entries.Length) + 1;
   end Next_Id;

   function Key_For
     (Components : Archive.Types.String_Vectors.Vector;
      Last       : Natural)
      return String
   is
      Result : Unbounded_String;
      Count  : Natural := 0;
   begin
      for Component of Components loop
         exit when Count = Last;
         if Length (Result) > 0 then
            Append (Result, "/");
         end if;
         Append (Result, Component);
         Count := Count + 1;
      end loop;
      return To_String (Result);
   end Key_For;

   procedure Append_Entry
     (Index : in out Archive_Index;
      Item  : Archive.Archives.Entries.Archive_Entry)
   is
   begin
      Index.Entries.Append (Item);
      if Item.Synthetic then
         Index.Synthetics := Index.Synthetics + 1;
      else
         Index.Physicals := Index.Physicals + 1;
      end if;
   end Append_Entry;

   function Ensure_Directory
     (Index      : in out Archive_Index;
      Known      : in out Path_Maps.Map;
      Components : Archive.Types.String_Vectors.Vector;
      Depth      : Natural;
      Parent     : Archive.Types.Entry_Id;
      Max_Synthetic : Natural;
      Limit_Hit  : in out Boolean)
      return Archive.Types.Entry_Id
   is
      Key : constant String := Key_For (Components, Depth);
   begin
      if Key = "" then
         return Index.Root;
      elsif Known.Contains (Key) then
         return Known.Element (Key);
      else
         declare
            Name : constant String := To_String (Components.Element (Positive (Depth)));
            Id   : constant Archive.Types.Entry_Id := Next_Id (Index);
            Item : Archive.Archives.Entries.Archive_Entry;
         begin
            if Index.Synthetics >= Max_Synthetic then
               Limit_Hit := True;
               return Archive.Types.No_Entry;
            end if;

            Item.Id := Id;
            Item.Ordinal := Archive.Types.Archive_Ordinal (Index.Entries.Length);
            Item.Original_Path := To_Unbounded_String (Key);
            Item.Display_Name := To_Unbounded_String (Name);
            Item.Parent := Parent;
            Item.Synthetic := True;
            Item.Kind := Archive.Archives.Entries.Directory;
            Item.Method := Archive.Archives.Entries.No_Compression;
            Item.Encryption := Archive.Archives.Entries.Not_Encrypted;
            Item.Integrity := Archive.Archives.Entries.Not_Available;
            Item.Safety := Archive.Archives.Entries.Safe_Path;
            Append_Entry (Index, Item);
            Known.Insert (Key, Id);
            return Id;
         end;
      end if;
   end Ensure_Directory;

   function Build
     (Physical : Archive.Archives.Entries.Entry_Vectors.Vector)
      return Build_Result
   is
   begin
      return Build_With_Limits
        (Physical,
         Max_Physical =>
           Natural
             (Archive.Resource_Limits.Default_Configured
                (Archive.Resource_Limits.Physical_Entry_Count)),
         Max_Synthetic =>
           Natural
             (Archive.Resource_Limits.Default_Configured
                (Archive.Resource_Limits.Synthetic_Directory_Count)));
   end Build;

   function Build_With_Limits
     (Physical      : Archive.Archives.Entries.Entry_Vectors.Vector;
      Max_Physical  : Natural;
      Max_Synthetic : Natural)
      return Build_Result
   is
      Result : Build_Result;
      Known  : Path_Maps.Map;
      Root   : Archive.Archives.Entries.Archive_Entry;
      Limit_Hit : Boolean := False;
   begin
      if Max_Physical < Natural (Physical.Length) or else Max_Synthetic = 0 then
         return (Status => Failed, Index => <>);
      end if;

      Root.Id := 1;
      Root.Ordinal := 0;
      Root.Original_Path := To_Unbounded_String ("");
      Root.Display_Name := To_Unbounded_String ("/");
      Root.Parent := Archive.Types.No_Entry;
      Root.Synthetic := True;
      Root.Kind := Archive.Archives.Entries.Directory;
      Root.Method := Archive.Archives.Entries.No_Compression;
      Root.Encryption := Archive.Archives.Entries.Not_Encrypted;
      Root.Integrity := Archive.Archives.Entries.Not_Available;
      Root.Safety := Archive.Archives.Entries.Safe_Path;
      Result.Index.Root := Root.Id;
      Append_Entry (Result.Index, Root);

      for Original of Physical loop
         declare
            Path_Text : constant String := To_String (Original.Original_Path);
            Norm      : constant Archive.Archives.Paths.Normalization_Result :=
              Archive.Archives.Paths.Normalize (Path_Text);
            Parent    : Archive.Types.Entry_Id := Result.Index.Root;
            Component_Count : constant Natural := Natural (Norm.Components.Length);
            Item      : Archive.Archives.Entries.Archive_Entry := Original;
         begin
            if Component_Count > 1 then
               for Depth in 1 .. Component_Count - 1 loop
                  Parent :=
                    Ensure_Directory
                      (Result.Index, Known, Norm.Components, Depth, Parent,
                       Max_Synthetic, Limit_Hit);
                  if Limit_Hit then
                     return (Status => Failed, Index => <>);
                  end if;
               end loop;
            end if;

            Item.Id := Next_Id (Result.Index);
            Item.Ordinal := Archive.Types.Archive_Ordinal (Result.Index.Physicals);
            Item.Parent := Parent;
            Item.Synthetic := False;
            Item.Safety := Norm.Safety;
            if Length (Item.Display_Name) = 0 then
               if Component_Count > 0 then
                  Item.Display_Name := Norm.Components.Last_Element;
               else
                  Item.Display_Name :=
                    To_Unbounded_String (Archive.Archives.Paths.Safe_Display_Name (Path_Text));
               end if;
            end if;
            Append_Entry (Result.Index, Item);
            if Item.Kind = Archive.Archives.Entries.Directory
              and then Item.Safety = Archive.Archives.Entries.Safe_Path
              and then Component_Count > 0
            then
               declare
                  Directory_Key : constant String := Key_For (Norm.Components, Component_Count);
               begin
                  if not Known.Contains (Directory_Key) then
                     Known.Insert (Directory_Key, Item.Id);
                  end if;
               end;
            end if;
         end;
      end loop;

      return Result;
   end Build_With_Limits;

   function Root_Id (Index : Archive_Index) return Archive.Types.Entry_Id is (Index.Root);
   function Entry_Count (Index : Archive_Index) return Natural is (Natural (Index.Entries.Length));
   function Physical_Count (Index : Archive_Index) return Natural is (Index.Physicals);
   function Synthetic_Count (Index : Archive_Index) return Natural is (Index.Synthetics);

   function Contains (Index : Archive_Index; Id : Archive.Types.Entry_Id) return Boolean is
   begin
      for Item of Index.Entries loop
         if Item.Id = Id then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Entry_For
     (Index : Archive_Index;
      Id    : Archive.Types.Entry_Id)
      return Archive.Archives.Entries.Archive_Entry
   is
   begin
      for Item of Index.Entries loop
         if Item.Id = Id then
            return Item;
         end if;
      end loop;
      return (others => <>);
   end Entry_For;

   function Children
     (Index  : Archive_Index;
      Parent : Archive.Types.Entry_Id)
      return Archive.Types.Entry_Id_Vectors.Vector
   is
      Result : Archive.Types.Entry_Id_Vectors.Vector;
   begin
      for Item of Index.Entries loop
         if Item.Parent = Parent then
            Result.Append (Item.Id);
         end if;
      end loop;
      return Result;
   end Children;
end Archive.Archives.Index;
