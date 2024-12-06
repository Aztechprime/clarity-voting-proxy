# Voting Proxy System

A blockchain-based voting proxy system implemented on the Stacks network using Clarity.

## Features

- Delegate voting rights to another address
- Revoke delegated voting rights
- Create proposals (contract owner only)
- Vote on active proposals
- View delegation status and proposal details

## Security Features

- Only authorized addresses can vote (original voter or their delegate)
- One-way delegation to prevent circular delegations
- Only contract owner can create proposals
- Immutable voting records

## Use Cases

- DAO governance
- Shareholder voting
- Community decision making
- Any scenario requiring secure vote delegation
