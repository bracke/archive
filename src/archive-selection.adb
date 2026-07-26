package body Archive.Selection is
   use type Archive.Types.Entry_Id;

   function Position
     (Values : Archive.Types.Entry_Id_Vectors.Vector;
      Id     : Archive.Types.Entry_Id)
      return Natural
   is
      Pos : Natural := 1;
   begin
      for Existing of Values loop
         if Existing = Id then
            return Pos;
         end if;
         Pos := Pos + 1;
      end loop;
      return 0;
   end Position;

   procedure Clear (Model : in out Selection_Model) is
   begin
      Model.Values.Clear;
      Model.Anchor_Value := Archive.Types.No_Entry;
   end Clear;

   procedure Select_Only (Model : in out Selection_Model; Id : Archive.Types.Entry_Id) is
   begin
      Model.Values.Clear;
      if Id /= Archive.Types.No_Entry then
         Model.Values.Append (Id);
      end if;
      Model.Anchor_Value := Id;
   end Select_Only;

   procedure Add (Model : in out Selection_Model; Id : Archive.Types.Entry_Id) is
   begin
      if Id /= Archive.Types.No_Entry and then not Contains (Model, Id) then
         Model.Values.Append (Id);
      end if;
      if Model.Anchor_Value = Archive.Types.No_Entry then
         Model.Anchor_Value := Id;
      end if;
   end Add;

   procedure Remove (Model : in out Selection_Model; Id : Archive.Types.Entry_Id) is
      Pos : constant Natural := Position (Model.Values, Id);
   begin
      if Pos > 0 then
         Model.Values.Delete (Positive (Pos));
      end if;
      if Model.Anchor_Value = Id then
         if Model.Values.Is_Empty then
            Model.Anchor_Value := Archive.Types.No_Entry;
         else
            Model.Anchor_Value := Model.Values.First_Element;
         end if;
      end if;
   end Remove;

   procedure Toggle (Model : in out Selection_Model; Id : Archive.Types.Entry_Id) is
   begin
      if Contains (Model, Id) then
         Remove (Model, Id);
      else
         Add (Model, Id);
         Model.Anchor_Value := Id;
      end if;
   end Toggle;

   procedure Select_Range
     (Model      : in out Selection_Model;
      Projection : Archive.Types.Entry_Id_Vectors.Vector;
      Anchor     : Archive.Types.Entry_Id;
      Target     : Archive.Types.Entry_Id)
   is
      Anchor_Pos : constant Natural := Position (Projection, Anchor);
      Target_Pos : constant Natural := Position (Projection, Target);
      First      : Natural;
      Last       : Natural;
   begin
      if Anchor_Pos = 0 or else Target_Pos = 0 then
         return;
      end if;

      if Anchor_Pos <= Target_Pos then
         First := Anchor_Pos;
         Last := Target_Pos;
      else
         First := Target_Pos;
         Last := Anchor_Pos;
      end if;

      Model.Values.Clear;
      for Pos in First .. Last loop
         Model.Values.Append (Projection.Element (Positive (Pos)));
      end loop;
      Model.Anchor_Value := Anchor;
   end Select_Range;

   function Contains (Model : Selection_Model; Id : Archive.Types.Entry_Id) return Boolean is
   begin
      return Position (Model.Values, Id) > 0;
   end Contains;

   function Count (Model : Selection_Model) return Natural is
   begin
      return Natural (Model.Values.Length);
   end Count;

   function Items (Model : Selection_Model) return Archive.Types.Entry_Id_Vectors.Vector is
   begin
      return Model.Values;
   end Items;

   function Anchor (Model : Selection_Model) return Archive.Types.Entry_Id is
   begin
      return Model.Anchor_Value;
   end Anchor;
end Archive.Selection;
