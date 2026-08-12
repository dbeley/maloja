{
  description = "Maloja - Self-hosted music scrobble database";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystemsWithPkgs = f: forAllSystems (system: f system nixpkgs.legacyPackages.${system});

      pythonVersion = "312";

      mkApp = drv: {
        type = "app";
        program = "${drv}/bin/maloja";
      };

    in
    {
      # NixOS module for installing Maloja as a system service
      nixosModules.maloja =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        with lib;
        let
          cfg = config.services.maloja;
          toEnv = name: "MALOJA_" + lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] name);
          toVal = v: if builtins.isBool v then (if v then "true" else "false") else toString v;
        in
        {
          options.services.maloja = {
            enable = mkEnableOption "Maloja scrobble server";

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.system}.default;
            };

            dataDir = mkOption {
              type = types.str;
              default = "/var/lib/maloja";
            };

            host = mkOption {
              type = types.str;
              default = "127.0.0.1";
            };

            port = mkOption {
              type = types.port;
              default = 42010;
            };

            settings = mkOption {
              type = types.attrsOf (
                types.nullOr (
                  types.oneOf [
                    types.str
                    types.int
                    types.bool
                    types.path
                  ]
                )
              );
              default = { };
              example = {
                theme = "dark";
                location_timezone = "Europe/Berlin";
              };
              description = "MALOJA_* env vars. Prefer environmentFile for secrets.";
            };

            environmentFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = "KEY=VALUE lines, overrides settings. Use for secrets.";
            };
          };

          config = mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];

            systemd.services.maloja = {
              description = "Maloja Music Scrobble Server";
              after = [
                "network.target"
                "sops-nix.service"
              ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "simple";
                ExecStart = "${cfg.package}/bin/maloja run";
                Restart = "on-failure";
                RestartSec = "10";
                DynamicUser = true;
                StateDirectory = "maloja";
                LogsDirectory = "maloja";
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
                BindReadOnlyPaths = [ "/run/secrets" ];
                Environment = [
                  "MALOJA_HOST=${cfg.host}"
                  "MALOJA_PORT=${toString cfg.port}"
                  "MALOJA_DATA_DIRECTORY=${cfg.dataDir}"
                ]
                ++ mapAttrsToList (n: v: "${toEnv n}=${toVal v}") (filterAttrs (n: v: v != null) cfg.settings);
              }
              // optionalAttrs (cfg.environmentFile != null) {
                EnvironmentFile = cfg.environmentFile;
              };

              preStart = ''
                mkdir -p ${cfg.dataDir}/{config,state,cache,logs}
              '';
            };
          };
        };

      # Development shell
      devShells = forAllSystemsWithPkgs (
        system: pkgs:
        let
          python = pkgs.${"python${pythonVersion}"};
          pyPkgs = python.withPackages (
            ps: with ps; [
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
            ]
          );
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
        }
      );

      # Packages
      packages = forAllSystemsWithPkgs (
        system: pkgs:
        let
          python = pkgs.${"python${pythonVersion}"};

          doreah = python.pkgs.buildPythonPackage rec {
            pname = "doreah";
            version = "2.0.1";
            src = python.pkgs.fetchPypi {
              inherit pname version;
              sha256 = "sha256-vbRtr/KED8qgLMj5bD7oSTpFjrQ3S2pph/QTs/Z0HL8=";
            };
            pyproject = true;
            nativeBuildInputs = with python.pkgs; [ flit-core ];
            propagatedBuildInputs = with python.pkgs; [
              requests
              pyyaml
              jinja2
              bcrypt
            ];
          };

          nimrodel = python.pkgs.buildPythonPackage rec {
            pname = "nimrodel";
            version = "0.8.0";
            src = python.pkgs.fetchPypi {
              inherit pname version;
              sha256 = "sha256-f9XVuvMXMAgqlDyDsZTF7Afquj9L/0U/4xVsN+VgtW0=";
            };
            pyproject = true;
            nativeBuildInputs = with python.pkgs; [ flit-core ];
            propagatedBuildInputs = with python.pkgs; [
              bottle
              waitress
              doreah
              parse
            ];
          };

          datauri' = python.pkgs.buildPythonPackage rec {
            pname = "python-datauri";
            version = "3.0.2";
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/source/p/python-datauri/python_datauri-3.0.2.tar.gz";
              hash = "sha256-13w38fc0/ANd5CTmQ0ZJkLK4QOm4x8GBfBH8oZtx7rc=";
            };
            pyproject = true;
            nativeBuildInputs = with python.pkgs; [ setuptools ];
            doCheck = false;
            propagatedBuildInputs = [
              python.pkgs."cached-property"
              python.pkgs."typing-extensions"
            ];
          };

          pythonEnv = python.withPackages (
            ps: with ps; [
              bottle
              waitress
              doreah
              nimrodel
              setproctitle
              jinja2
              lru-dict
              psutil
              sqlalchemy
              datauri'
              python-magic
              requests
              toml
              pyyaml
            ]
          );
        in
        {
          default = python.pkgs.buildPythonPackage rec {
            pname = "malojaserver";
            version = "3.2.5";
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
              datauri'
              python-magic
              requests
              toml
              pyyaml
            ];

            # No tests available in the repository
            doCheck = false;
            postPatch = ''
              substituteInPlace pyproject.toml --replace-quiet '"psutil>=5.9,<7.0"' '"psutil>=5.9"'
            '';

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
              Cmd = [
                "maloja"
                "run"
              ];
              ExposedPorts = {
                "42010/tcp" = { };
              };
              Env = [
                "MALOJA_SKIP_SETUP=yes"
                "MALOJA_DATA_DIRECTORY=/data"
              ];
              Volumes = {
                "/data" = { };
              };
            };
          };
        }
      );

      # Apps
      apps = forAllSystemsWithPkgs (
        system: pkgs: {
          default = mkApp self.packages.${system}.default;
        }
      );

      # Formatter (nix fmt)
      formatter = forAllSystemsWithPkgs (system: pkgs: pkgs.nixfmt-rfc-style);
    };
}
