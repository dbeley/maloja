{
  description = "Maloja - Self-hosted music scrobble database";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystemsWithPkgs = f:
        forAllSystems (system: f system nixpkgs.legacyPackages.${system});

      pythonVersion = "312";

      mkApp = drv: {
        type = "app";
        program = "${drv}/bin/maloja";
      };

    in {
      # NixOS module for installing Maloja as a system service
      nixosModules.maloja = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.maloja;
          malojaPackage = self.packages.${pkgs.system}.default;

          toEnvName = name: "MALOJA_" + lib.toUpper (builtins.replaceStrings ["-"] ["_"] name);
          toEnvValue = value:
            if builtins.isBool value then (if value then "true" else "false")
            else toString value;
          settingsToEnv = attrs:
            mapAttrsToList (n: v: "${toEnvName n}=${toEnvValue v}")
              (filterAttrs (n: v: v != null) attrs);
        in {
          options.services.maloja = {
            enable = mkEnableOption "Maloja scrobble server";

            package = mkOption {
              type = types.package;
              default = malojaPackage;
              description = "Maloja package to use";
            };

            dataDir = mkOption {
              type = types.str;
              default = "/var/lib/maloja";
              description = "Data directory for Maloja";
            };

            host = mkOption {
              type = types.str;
              default = "*";
              description = "Host to bind to. Set to 127.0.0.1 if using the nginx reverse proxy.";
            };

            port = mkOption {
              type = types.port;
              default = 42010;
              description = "Port to listen on";
            };

            configFile = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Path to custom settings.ini file directory. Overrides settings option for equivalent keys.";
            };

            openFirewall = mkOption {
              type = types.bool;
              default = false;
              description = "Open port in firewall";
            };

            followLastfmUsername = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Last.fm username to periodically import scrobbles from. Requires lastfmApiKey to be set.";
            };

            lastfmApiKey = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Last.fm API key (required for followLastfmUsername and image metadata). Prefer environmentFile for secrets.";
            };

            settings = mkOption {
              type = types.attrsOf (types.nullOr (types.oneOf [ types.str types.int types.bool types.path ]));
              default = { };
              example = {
                theme = "dark";
                name = "My Maloja";
                scrobbles_gold = 100;
                location_timezone = "Europe/Berlin";
              };
              description = ''
                Additional settings passed as MALOJA_* environment variables.
                See settings.md for all available options.
                Prefer environmentFile for secrets like API keys.
              '';
            };

            environmentFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                File containing environment variables (KEY=VALUE lines) passed to the
                maloja service. Use this for secrets like API keys instead of putting
                them in the nix store. File is re-read on service restart.
                These override both explicit options and settings with the same key.
              '';
            };

            nginx = {
              enable = mkEnableOption "nginx reverse proxy for Maloja";

              domain = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Domain name for the Maloja web interface. Required for ACME/SSL.";
              };

              serverAliases = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Additional domain names";
              };

              ssl = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable SSL via ACME (requires domain to be set)";
                };

                autoEnable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Automatically request ACME certificate";
                };
              };

              extraConfig = mkOption {
                type = types.lines;
                default = "";
                description = "Additional nginx virtual host configuration";
              };
            };
          };

          config = mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];

            systemd.services.maloja = {
              description = "Maloja Music Scrobble Server";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "simple";
                ExecStart = "${cfg.package}/bin/maloja run";
                Restart = "on-failure";
                RestartSec = "10";
                User = "maloja";
                Group = "maloja";
                StateDirectory = "maloja";
                StateDirectoryMode = "0755";
                LogsDirectory = "maloja";
                LogsDirectoryMode = "0755";
                AmbientCapabilities = "";
                CapabilityBoundingSet = "";
                NoNewPrivileges = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                PrivateDevices = true;
                ProtectKernelTunables = true;
                ProtectKernelModules = true;
                ProtectControlGroups = true;
                MemoryDenyWriteExecute = false;
                ReadWritePaths = [ cfg.dataDir ];
                Environment =
                  [ "MALOJA_HOST=${cfg.host}"
                    "MALOJA_PORT=${toString cfg.port}"
                  ]
                  ++ (if cfg.configFile != null then
                    [ "MALOJA_DIRECTORY_CONFIG=${cfg.configFile}" ]
                  else
                    [ "MALOJA_DATA_DIRECTORY=${cfg.dataDir}" ]
                  )
                  ++ lib.optional (cfg.followLastfmUsername != null) "MALOJA_FOLLOW_LASTFM_USERNAME=${cfg.followLastfmUsername}"
                  ++ lib.optional (cfg.lastfmApiKey != null) "MALOJA_LASTFM_API_KEY=${cfg.lastfmApiKey}"
                  ++ settingsToEnv cfg.settings;
              } // lib.optionalAttrs (cfg.environmentFile != null) {
                EnvironmentFile = cfg.environmentFile;
              };

              preStart = ''
                mkdir -p ${cfg.dataDir}/{config,state,cache,logs}
              '';
            };

            services.nginx = mkIf cfg.nginx.enable {
              enable = true;
              virtualHosts = lib.optionalAttrs (cfg.nginx.domain != null) {
                "${cfg.nginx.domain}" = {
                  serverName = cfg.nginx.domain;
                  serverAliases = cfg.nginx.serverAliases;
                  locations."/" = {
                    proxyPass = "http://127.0.0.1:${toString cfg.port}";
                    proxyWebsockets = true;
                    recommendedProxySettings = true;
                  };
                  extraConfig = cfg.nginx.extraConfig;
                } // lib.optionalAttrs (cfg.nginx.ssl.enable) {
                  enableACME = cfg.nginx.ssl.autoEnable;
                  forceSSL = true;
                };
              };
            };

            networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall (
              if cfg.nginx.enable && cfg.nginx.domain != null && cfg.nginx.ssl.enable
              then [ 80 443 ]
              else [ cfg.port ]
            );
          };
        };

      # Development shell
      devShells = forAllSystemsWithPkgs (system: pkgs:
        let
          python = pkgs.${"python${pythonVersion}"};
          pyPkgs = python.withPackages (ps: with ps; [
            bottle
            waitress
            setproctitle
            jinja2
            lru-dict
            psutil
            sqlalchemy
            python-magic
            requests
            toml
            pyyaml
            pyvips
          ]);
        in
        {
        default = pkgs.mkShell {
          packages = with pkgs; [
            pyPkgs
            (python.pkgs.datauri.overridePythonAttrs {
              dontCheckPythonMetadata = true;
            })
            sqlite-interactive
            sqlitebrowser
            gnumake
          ];

          shellHook = ''
            echo "Maloja development shell"
            echo "Run 'maloja run' to start the server"
            echo "Run 'MALOJA_DATA_DIRECTORY=./data maloja run' to use a local data directory"
          '';

          MALOJA_DATA_DIRECTORY = "./data";
          MALOJA_SKIP_SETUP = "yes";
        };
      });

      # Packages
      packages = forAllSystemsWithPkgs (system: pkgs:
        let
          python = pkgs.${"python${pythonVersion}"};
          pythonEnv = python.withPackages (ps: with ps; [
            bottle
            waitress
            doreah
            nimrodel
            setproctitle
            jinja2
            lru-dict
            psutil
              sqlalchemy
              datauri
              python-magic
            requests
            toml
            pyyaml
          ]);
        in {
          default = python.pkgs.buildPythonPackage rec {
            pname = "malojaserver";
            version = "3.2.4";
            pyproject = true;

            src = ./.;

            nativeBuildInputs = with pkgs; [
              python.pkgs.flit-core
              python.pkgs.setuptools
              python.pkgs.wheel
            ];

            propagatedBuildInputs = with python.pkgs; [
              bottle
              waitress
              doreah
              nimrodel
              setproctitle
              jinja2
              lru-dict
              psutil
              sqlalchemy
              python-datauri
              python-magic
              requests
              toml
              pyyaml
            ];

            # No tests available in the repository
            doCheck = false;

            meta = with pkgs.lib; {
              description = "Self-hosted music scrobble database";
              homepage = "https://github.com/dbeley/maloja";
              license = licenses.gpl3Only;
              maintainers = [ ];
              platforms = platforms.linux;
              mainProgram = "maloja";
            };
          };

          docker = pkgs.dockerTools.buildImage {
            name = "maloja";
            tag = "latest";
            copyToRoot = pkgs.buildEnv {
              name = "image-root";
              paths = [ self.packages.${system}.default ];
              pathsToLink = [ "/bin" ];
            };
            config = {
              Cmd = [ "maloja" "run" ];
              ExposedPorts = { "42010/tcp" = { }; };
              Env = [
                "MALOJA_SKIP_SETUP=yes"
                "MALOJA_DATA_DIRECTORY=/data"
              ];
              Volumes = { "/data" = { }; };
            };
          };
        });

      # Apps
      apps = forAllSystemsWithPkgs (system: pkgs: {
        default = mkApp self.packages.${system}.default;
      });

      # Formatter (nix fmt)
      formatter = forAllSystemsWithPkgs (system: pkgs: pkgs.nixfmt-rfc-style);
    };
}
