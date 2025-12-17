# AWS Connection Scripts

A collection of bash scripts for connecting to AWS resources via AWS Systems Manager (SSM) Session Manager.

## Scripts

| Script | Description |
|--------|-------------|
| `connect-ec2` | Connect to EC2 instances via SSM Session Manager |
| `connect-ecs` | Connect to ECS tasks/containers via SSM Session Manager |
| `connect-rds` | Connect to RDS databases (sets up port forwarding and retrieves credentials from Secrets Manager) |

## Features

- 🔐 Handles AWS authentication automatically
- 🎯 Interactive selection of AWS profiles, regions, and resources
- 🐛 Debug mode (`--debug` or `-d` flag)
- 🎨 Colored terminal output
- ⚡ Works with AWS SSO and IAM credentials

## Prerequisites

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- Configured AWS profiles (`~/.aws/config`)
- For `connect-rds`: PostgreSQL client (`psql`) or MySQL client

### Install on macOS

```bash
# AWS CLI
brew install awscli

# Session Manager Plugin
brew install --cask session-manager-plugin

# PostgreSQL client (for RDS)
brew install libpq && brew link --force libpq
```

### Install on Linux (Ubuntu/Debian)

```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Session Manager Plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb

# PostgreSQL client (for RDS)
sudo apt-get install postgresql-client
```

## Installation

### Step 1: Clone the repository

```bash
git clone git@github.com:MaksShyshkin/scripts.git ~/scripts
# or using HTTPS:
git clone https://github.com/MaksShyshkin/scripts.git ~/scripts
```

### Step 2: Make scripts executable

```bash
chmod +x ~/scripts/*.sh
```

### Step 3: Add to PATH

Choose one of the following options:

#### Option A: Add scripts directory to PATH (Recommended)

Add this line to your shell configuration file:

**For Zsh (`~/.zshrc`):**
```bash
echo 'export PATH="$PATH:$HOME/scripts"' >> ~/.zshrc
source ~/.zshrc
```

**For Bash (`~/.bashrc` or `~/.bash_profile`):**
```bash
echo 'export PATH="$PATH:$HOME/scripts"' >> ~/.bashrc
source ~/.bashrc
```

#### Option B: Create symlinks in /usr/local/bin

```bash
sudo ln -s ~/scripts/connect-ec2 /usr/local/bin/connect-ec2
sudo ln -s ~/scripts/connect-ecs /usr/local/bin/connect-ecs
sudo ln -s ~/scripts/connect-rds /usr/local/bin/connect-rds
```

#### Option C: Create aliases

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
alias connect-ec2='~/scripts/connect-ec2'
alias connect-ecs='~/scripts/connect-ecs'
alias connect-rds='~/scripts/connect-rds'
```

Then reload: `source ~/.zshrc` or `source ~/.bashrc`

### Step 4: Verify installation

```bash
# Check if scripts are accessible
which connect-ec2
which connect-ecs
which connect-rds

# Test a script
connect-ec2 --help
```

## Usage

After installation, run from any directory:

```bash
# Connect to an EC2 instance
connect-ec2

# Connect to an ECS task
connect-ecs

# Connect to an RDS database
connect-rds

# Enable debug mode
connect-ec2 --debug
connect-ecs -d
```

## Troubleshooting

### "command not found" after adding to PATH

1. Make sure you reloaded your shell config: `source ~/.zshrc`
2. Verify PATH includes the scripts directory: `echo $PATH`
3. Check scripts are executable: `ls -la ~/scripts/`

### Permission denied

```bash
chmod +x ~/scripts/*.sh
```

### AWS credentials not working

1. Verify AWS CLI is configured: `aws configure list`
2. For SSO, run: `aws sso login --profile <your-profile>`

## Security

- No credentials are stored in these scripts
- All AWS credentials are retrieved dynamically via AWS CLI/SSO
- Database passwords are fetched from AWS Secrets Manager at runtime

## License

MIT
