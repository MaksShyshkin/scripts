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

## Installation

### Option 1: Add scripts directory to PATH (Recommended)

Add this line to your shell configuration file (`~/.zshrc` or `~/.bashrc`):

```bash
export PATH="$PATH:/Users/mshyshkin/IdeaProjects/scripts"
```

Then reload your shell:

```bash
source ~/.zshrc  # or source ~/.bashrc
```

### Option 2: Create symlinks in /usr/local/bin

```bash
ln -s /Users/mshyshkin/IdeaProjects/scripts/connect-ec2 /usr/local/bin/connect-ec2
ln -s /Users/mshyshkin/IdeaProjects/scripts/connect-ecs /usr/local/bin/connect-ecs
ln -s /Users/mshyshkin/IdeaProjects/scripts/connect-rds /usr/local/bin/connect-rds
```

### Option 3: Create aliases

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
alias connect-ec2='/Users/mshyshkin/IdeaProjects/scripts/connect-ec2'
alias connect-ecs='/Users/mshyshkin/IdeaProjects/scripts/connect-ecs'
alias connect-rds='/Users/mshyshkin/IdeaProjects/scripts/connect-rds'
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

## License

MIT
