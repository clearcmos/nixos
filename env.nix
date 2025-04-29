# Environment variables for NixOS configurations
{ lib, ... }:

let
  # Helper function to load environment variables from .env file
  loadEnv = path:
    let
      content = builtins.readFile path;
      lines = lib.filter (line:
        line != "" &&
        !(lib.hasPrefix "#" line)
      ) (lib.splitString "\n" content);

      parseLine = line:
        let
          match = builtins.match "([^=]+)=([\"']?)([^\"]*)([\"']?)" line;
          key = if match == null then null else lib.elemAt match 0;
          value = if match == null then null else lib.elemAt match 2;
        in if match == null
           then null
           else { name = lib.removeSuffix " " (lib.removePrefix " " key); value = value; };

      parsedLines = map parseLine lines;
      validLines = builtins.filter (x: x != null) parsedLines;
      env = builtins.listToAttrs validLines;
    in env;

  # Load environment variables from .env file
  envVars = loadEnv ./.env;
  
  # Convert netmask to prefix length (e.g., 255.255.255.0 -> 24)
  netmaskToPrefixLength = netmask:
    let
      # Convert netmask to binary string
      toBinary = n: lib.fixedWidthString 8 "0" (lib.toBaseDigits 2 (lib.toInt n));
      
      # Split netmask into octets and convert each to binary
      parts = lib.splitString "." netmask;
      binaryParts = map toBinary parts;
      
      # Concatenate to single binary string
      binaryString = lib.concatStrings binaryParts;
      
      # Count leading "1"s to get prefix length
      prefixMatch = builtins.match "1*0*" binaryString;
      prefixLength = if prefixMatch == null 
                    then 24  # Fallback if invalid netmask
                    else lib.stringLength (builtins.elemAt prefixMatch 0);
    in prefixLength;
  
in {
  # Make environment variables available to other modules
  _module.args = {
    env = envVars;
    # Also export the helper function for use in other modules
    netmaskToPrefixLength = netmaskToPrefixLength;
  };
}