{
  description = "Porkbun's minimalist dynamic DNS client in Python";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils, ... }: let
    name = "porkbun-ddns"; 
  in
    flake-utils.lib.eachDefaultSystem(system: let

      pkgs = import nixpkgs { inherit system; };

      pkg = let
        inherit (pkgs.python3Packages)
          buildPythonApplication
          requests
        ; 
      in buildPythonApplication {
        pname = name;
        version = "3.0";
        propagatedBuildInputs = [ requests ];
        src = ./.;
      };

    in {
      packages.default = pkg;
      packages.${name} = pkg;

    }) // { 

      nixosModules = {
        default = self.nixosModules.${name}; 
        ${name} = (
          { config, pkgs, lib, ... }: with lib; let 
            cfg = config.services.${name}; 
            pkg = self.packages.${pkgs.system}.default;
          in {
            options.services.${name} = {

              enable = mkEnableOption self.description;

              user = mkOption {
                type = types.str;
                default = name;
                description = lib.mdDoc ''
                  User account under which ${name} runs.
                '';
              };

              group = mkOption {
                type = types.str;
                default = name;
                description = lib.mdDoc ''
                  Group under which ${name} runs.
                '';
              };

              defaultApiConfigFile = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              defaultApiConfig = {

                endpoint = mkOption {
                  type = types.str;
                  default = "https://api-ipv4.porkbun.com/api/json/v3";
                  description = lib.mdDoc ''
                    URL to the API endpoint.
                  '';
                };
                
                apiKey = mkOption {
                  type = types.str;
                  default = "pk1_c3d12db3f33b49c69df7d7fc67cd090dc8a1b385ae65c150376f08be194470f6";
                  description = lib.mdDoc ''
                    Public key of the API.
                  '';
                };

                secretApiKey = mkOption {
                  type = types.str;
                  description = lib.mdDoc ''
                    Secret key of your account. 

                    - Any string beginning with `sk1_` is assumed to be a secret key 
                    and is passed directly.

                    - Any string not beginning with `sk1_` is assumed to be a path
                    and has its content passed as the secret key.
                  '';
                };

              };


              rootDomain = mkOption {
                type = types.str;
                description = lib.mdDoc ''
                  Which root domain to target. 

                  Might not have its own DNS records modified
                  if `subDomain` is set.
                '';
              };

              subDomain = mkOption {
                type = types.nullOr types.str;
                default = "";
                description = ''
                  Which subdomain, if any, to target. 

                  If set to null (the default), target only the root domain.

                  Setting a wildcard DNS record (`*`) is supported.
                '';
              };

              manualIPAdress = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Instead of detecting the external IP address, set it manually to this IP.

                  If set to null (the default), detect the external IP address as usual.

                  If not set to null, the `subDomain` option is ignored since only
                  wildcard DNS records (`*`) are supported with this method.
                '';
              };
            };

            config = mkIf cfg.enable {

              users.groups = mkIf (cfg.group == name) {
                ${name} = { };
              };

              users.users = mkIf (cfg.user == name) {
                ${name} = {
                  group = cfg.group;
                  description = "${name} daemon user";
                  isSystemUser = true;
                };
              };

              systemd = let
                passedCfgFile = cfg.defaultApiConfigFile != null;
                cfgPath = if passedCfgFile then 
                            cfg.defaultApiConfigFile
                          else 
                            "/run/porkbun-ddns-config.json";
              in {

                tmpfiles.rules = with cfg.defaultApiConfig; let
                  jsonContent = builtins.toJSON {
                    "endpoint" = endpoint;
                    "apikey" = apiKey;
                    "secretapikey" = if lib.strings.hasPrefix "sk1_" secretApiKey then
                                       secretApiKey
                                     else
                                       builtins.readFile secretApiKey;
                  };
                in mkIf (!passedCfgFile) [
                  "f+ ${cfgPath} 440 ${cfg.user} ${cfg.group} - ${jsonContent}"
                ];

                timers.${name} = {
                  wantedBy = [ "timers.target" ];
                  after = [ "network.target" ];
                  timerConfig = {
                    OnBootSec = "5";
                    OnUnitActiveSec = "6h";
                    Unit = "${name}.service";
                  };
                };

                services.${name} = let
                  arg = if cfg.manualIPAdress != null then
                          "-i ${manualIPAdress}" 
                        else if cfg.subDomain == null then
                          ""
                        else if cfg.subDomain == "*" then
                          "'*'"
                        else
                          cfg.subDomain;
                  cmd = ''
                    ${pkg}/bin/${name}.py \
                    ${cfg.cfgPath} \
                    ${cfg.rootDomain} \
                    ${arg}
                  '';
                in {
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" ];
                  path = [ pkg ];
                  serviceConfig = {
                    User = cfg.user;
                    Group = cfg.group;
                    Type = "oneshot";
                    ExecStart=cmd;
                  };
                };
              };  
            };
          }
        );
      };  # nixosModules
    };
}

