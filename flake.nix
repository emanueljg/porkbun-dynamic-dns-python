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

              defaultApiConfig = mkOption {
                type = types.str;
                description = lib.mdDoc ''
                  Path to the API JSON configuration file. 

                  Jobs can override this default
                  to specify their own API configurations. 
                '';
              };

              jobs = mkOption {
                description = lib.mdDoc ''
                  List of jobs to carry out.
                '';
                type = types.listOf (types.submodule {
                  options = {

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

                    apiConfig = mkOption {
                      type = types.str;
                      default = cfg.defaultApiConfig;
                      description = ''
                        Optional per-job path to the API JSON configuration file. 
                      '';
                    };
                  
                  };
                });
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

              # define parent/controller unit
              systemd = {
                units.${name} = {
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" ];
                };

                timers.${name} = {
                  wantedBy = [ "timers.target" ];
                  timerConfig = {
                    OnBootSec = "5";
                    OnUnitActiveSec = "6h";
                    Unit = "${name}.unit";
                  };
                };
              };

              # define children
              systemd.services = let
                mkJobServiceValue = job: let 
                  arg = if job.manualIPAdress != null then
                          "-i ${job.manualIPAdress}" 
                        else if job.subDomain == null then
                          ""
                        else if job.subDomain == "*" then
                          "'*'"
                        else
                          job.subDomain;
                  cmd = ''
                    ${pkg}/bin/${name}.py \
                    ${job.apiConfig} \
                    ${job.rootDomain} \
                    ${arg}
                  '';
                in {
                  wantedBy = [ "${name}.unit" ];
                  after = [ "network.target" ];
                  path = [ pkg ];
                  serviceConfig = {
                    User = cfg.user;
                    Group = cfg.group;
                    Type = "oneshot";
                    ExecStart=cmd;
                  };
                };

                mkJobServiceName = job:
                  if job.subDomain == null then
                    "${name}-${job.rootDomain}"
                  else
                    "${name}-${job.subDomain}-${job.rootDomain}";

                mkJobNVPair = job: 
                  lib.attrsets.nameValuePair
                    (mkJobServiceName job)
                    (mkJobServiceValue job);

              in builtins.listToAttrs (
                lib.lists.forEach cfg.jobs mkJobNVPair
              );
            };
          }
        );
      };  # nixosModules
    };
}

