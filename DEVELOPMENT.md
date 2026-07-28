# Development

Clone the repository and enter it.

```console
	git clone https://github.com/dbeley/maloja
	cd maloja
```

## Environment (Docker)

Run the included `docker-compose.yml` file.
```console
	docker compose -f dev/docker-compose.yml -p maloja up --force-recreate --build
```

## Environment (Python venv)

To avoid cluttering your system, consider using a [virtual environment](https://docs.python.org/3/tutorial/venv.html).

With pip:
```console
	python3 -m venv .venv
	source .venv/bin/activate
	pip install -e .
```

With uv (recommended for faster installs):
```console
	uv sync
	source .venv/bin/activate
	# or: uv run maloja run
```

## Environment (NixOS / Nix Flake)

For NixOS or systems with Nix package manager installed, you can use the provided flake for development:

```console
	# Enter development shell with all dependencies
	nix develop

	# Or with direnv (automatic when entering the directory)
	direnv allow

	# Start the server once inside the nix shell
	maloja run
```

To install Maloja as a NixOS module on your system:

```nix
{
  inputs = {
    maloja.url = "github:dbeley/maloja";
  };

  # In your configuration.nix:
  imports = [ maloja.nixosModules.maloja ];

  services.maloja = {
    enable = true;
    port = 42010;
    openFirewall = true;
    # dataDir = "/var/lib/maloja";  # default
  };
}
```

## Running the server

Use the environment variable `MALOJA_DATA_DIRECTORY` to force all user files into one central directory - this way, you can also quickly change between multiple configurations.

```console
	MALOJA_DATA_DIRECTORY=./testdata maloja run
```

## Further help

Feel free to [ask](https://github.com/dbeley/maloja/discussions) if you need some help!
