# Clarity Governance Platform

A comprehensive blockchain-based governance platform implemented on the Stacks network using Clarity, featuring weighted voting, membership tiers, and token-gated voting capabilities.

## Features

### Core Voting Features
- Delegate voting rights to another address
- Revoke delegated voting rights
- Create and manage proposals
- Vote on active proposals with weighted voting power
- View delegation status and proposal details

### Enhanced Governance Capabilities
- Weighted voting based on token holdings or membership tier
- Multiple membership tiers with configurable voting power
- Token-gated voting integration with SIP-010 tokens
- Quadratic voting option for balanced decision making
- Time-locked proposal execution
- Proposal categorization and tagging

### Security Features
- Only authorized addresses can vote (original voter or their delegate)
- One-way delegation to prevent circular delegations
- Tiered access control system
- Token-based voting power snapshots
- Time-locked proposal execution
- Immutable voting records

## Membership System

### Tier Structure
- Basic Tier: Base voting power
- Silver Tier: 5x voting power
- Gold Tier: 10x voting power
- Platinum Tier: 20x voting power

### Membership Features
- Configurable voting power multipliers per tier
- Member history tracking
- Automatic tier-based vote weighting
- Membership status management
- Custom voting weight assignments

## Token Integration

### Token-Gated Voting
- SIP-010 token integration
- Configurable token voting weight
- Token balance snapshots for voting
- Optional token lockup for increased voting power
- Linear and square root voting power models

### Token Lockup Features
- Time-based token locking
- Multiplier-based voting power boost
- Flexible lock periods
- Automatic lock expiration

## Use Cases

- DAO governance
- Token-weighted voting systems
- Multi-tiered organizational governance
- Community decision making
- Shareholder voting
- Progressive governance rights
- Hybrid token/membership voting systems

## Contracts Overview

### voting-proxy
The main governance contract handling:
- Proposal creation and management
- Vote delegation
- Weighted voting execution
- Proposal execution logic

### membership-registry
Manages member tiers and voting rights:
- Tier creation and management
- Member registration
- Voting power calculation
- Member history tracking

### token-vote-power
Handles token-based voting capabilities:
- Token balance snapshots
- Voting power calculation
- Token lockup mechanism
- SIP-010 token integration

## Security Considerations

- Role-based access control
- Time-locked execution
- Snapshot-based voting
- Delegation safety checks
- Token integration safeguards
- Anti-manipulation mechanisms
- Quadratic voting option for vote buying protection

This platform provides a flexible and secure foundation for implementing complex governance systems on the Stacks blockchain, suitable for various organizational structures and voting requirements.