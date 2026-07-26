package Archive.Localization is
   function Normalize_Locale (Value : String) return String;
   function System_Locale return String;
   function Text (Key : String; Locale : String := "") return String;
end Archive.Localization;
