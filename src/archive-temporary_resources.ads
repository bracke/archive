with Archive.Types;

package Archive.Temporary_Resources is
   type Resource_Kind is
     (Gzip_Tar_Backing,
      Preview_File,
      Extraction_Temporary_File,
      Staging_Directory,
      Diagnostic_Report);

   type Resource_State is
     (Registered,
      Retained,
      Cleanup_Requested,
      Cleaned,
      Cleanup_Failed);

   type Cleanup_Decision is
     (Cleanup_Allowed,
      Cleanup_Rejected_Outside_Root,
      Cleanup_Rejected_Already_Final);

   type Resource_Id is new Natural;
   No_Resource : constant Resource_Id := 0;

   type Resource_Record is record
      Id          : Resource_Id := No_Resource;
      Kind        : Resource_Kind := Preview_File;
      Owner       : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Path        : Archive.Types.UString;
      State       : Resource_State := Registered;
   end record;

   type Resource_Array is array (Positive range <>) of Resource_Record;

   protected type Registry (Capacity : Positive) is
      procedure Register
        (Kind   : Resource_Kind;
         Owner  : Archive.Types.Generation_Id;
         Path   : String;
         Id     : out Resource_Id;
         Stored : out Boolean);

      procedure Request_Cleanup
        (Id       : Resource_Id;
         Temp_Root : String;
         Decision : out Cleanup_Decision);

      procedure Mark_Cleaned (Id : Resource_Id);
      procedure Mark_Failed (Id : Resource_Id);

      function Count return Natural;
      function Active_Count return Natural;
      function Contains (Id : Resource_Id) return Boolean;
      function Resource (Id : Resource_Id) return Resource_Record;
   private
      Items   : Resource_Array (1 .. Capacity);
      Used    : Natural := 0;
      Next_Id : Resource_Id := 1;
   end Registry;

   function Under_Root (Root : String; Path : String) return Boolean;

   function Fresh_Sibling_Path
     (Root   : String;
      Target : String;
      Role   : String)
      return String;
end Archive.Temporary_Resources;
