package body Archive.Navigation is
   use type Archive.Types.Entry_Id;
   use type Archive.Types.Generation_Id;

   procedure Drop_Forward (Model : in out Navigation_Model) is
   begin
      while Natural (Model.Entries.Length) > Model.Cursor loop
         Model.Entries.Delete_Last;
      end loop;
   end Drop_Forward;

   procedure Reset
     (Model   : in out Navigation_Model;
      Session : Archive.Types.Generation_Id;
      Root    : Archive.Types.Entry_Id)
   is
   begin
      Model.Entries.Clear;
      Model.Entries.Append
        (History_Entry'
           (Session => Session,
            Directory => Root,
            Focused => Archive.Types.No_Entry,
            Selection_Anchor => Archive.Types.No_Entry,
            Viewport_First => 0));
      Model.Cursor := 1;
   end Reset;

   procedure Navigate_To
     (Model     : in out Navigation_Model;
      Directory : Archive.Types.Entry_Id;
      Focused   : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Viewport  : Natural := 0)
   is
      Session : Archive.Types.Generation_Id := Archive.Types.No_Generation;
   begin
      if Model.Cursor > 0 then
         Session := Model.Entries.Element (Positive (Model.Cursor)).Session;
      end if;

      Drop_Forward (Model);
      Model.Entries.Append
        (History_Entry'
           (Session => Session,
            Directory => Directory,
            Focused => Focused,
            Selection_Anchor => Archive.Types.No_Entry,
            Viewport_First => Viewport));
      Model.Cursor := Natural (Model.Entries.Length);
   end Navigate_To;

   function Can_Back (Model : Navigation_Model) return Boolean is
   begin
      return Model.Cursor > 1;
   end Can_Back;

   function Can_Forward (Model : Navigation_Model) return Boolean is
   begin
      return Model.Cursor > 0 and then Model.Cursor < Natural (Model.Entries.Length);
   end Can_Forward;

   function Back (Model : in out Navigation_Model) return History_Entry is
   begin
      if Can_Back (Model) then
         Model.Cursor := Model.Cursor - 1;
      end if;
      return Current (Model);
   end Back;

   function Forward (Model : in out Navigation_Model) return History_Entry is
   begin
      if Can_Forward (Model) then
         Model.Cursor := Model.Cursor + 1;
      end if;
      return Current (Model);
   end Forward;

   function Current (Model : Navigation_Model) return History_Entry is
   begin
      if Model.Cursor = 0 then
         return (others => <>);
      end if;
      return Model.Entries.Element (Positive (Model.Cursor));
   end Current;
end Archive.Navigation;
