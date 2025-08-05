module move_gaming::slot_machine;

use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event;
use sui::random::{Self, Random};
use sui::sui::SUI;
use sui::table::{Self, Table};

// Error codes
const EInactiveGame: u64 = 0;
const EInsufficientBalance: u64 = 1;
const EInvalidBetAmount: u64 = 2;
const ENotOwner: u64 = 3;
const ENoRewardToClaim: u64 = 4;
const ERewardExpired: u64 = 5;

// Game constants
const MIN_BET: u64 = 100000; // 0.0001 SUI (100,000 MIST)
const MAX_BET: u64 = 10000000000; // 10 SUI
const REWARD_EXPIRY_TIME: u64 = 86400000; // 24 hours in milliseconds

// Slot symbols
const CHERRY: u8 = 0;
const LEMON: u8 = 1;
const ORANGE: u8 = 2;
const GRAPE: u8 = 3;
const WATERMELON: u8 = 4;
const DIAMOND: u8 = 5;
const SEVEN: u8 = 6;
const BELL: u8 = 7;
const LEAF: u8 = 8;
const CROWN: u8 = 9;

// Payout table (multipliers)
const TRIPLE_SEVEN: u64 = 1000;
const TRIPLE_DIAMOND: u64 = 500;
const TRIPLE_CROWN: u64 = 200;
const TRIPLE_LEAF: u64 = 100;
const TRIPLE_BELL: u64 = 50;
const TRIPLE_WATERMELON: u64 = 25;
const TRIPLE_GRAPE: u64 = 15;
const TRIPLE_ORANGE: u64 = 10;
const TRIPLE_LEMON: u64 = 5;
const TRIPLE_CHERRY: u64 = 3;

const SEVEN_LINE: u64 = 2;
const CHERRY_LINE: u64 = 1;

// Double symbol multipliers (2 reels match)
const DOUBLE_SEVEN: u64 = 190; // 1.9x
const DOUBLE_DIAMOND: u64 = 160; // 1.6x
const DOUBLE_CROWN: u64 = 150; // 1.5x
const DOUBLE_LEAF: u64 = 140; // 1.4x
const DOUBLE_BELL: u64 = 130; // 1.3x
const DOUBLE_WATERMELON: u64 = 120; // 1.2x
const DOUBLE_GRAPE: u64 = 115; // 1.15x
const DOUBLE_ORANGE: u64 = 112; // 1.12x
const DOUBLE_LEMON: u64 = 110; // 1.1x
const DOUBLE_CHERRY: u64 = 110; // 1.05x

// Struct to store active spins (waiting for result check)
public struct ActiveSpin has copy, drop, store {
    player: address,
    bet_amount: u64,
    timestamp: u64,
    reel1: u8,
    reel2: u8,
    reel3: u8,
    is_processed: bool,
}
public struct PendingReward has copy, drop, store {
    amount: u64,
    spin_id: u64,
    timestamp: u64,
    reel1: u8,
    reel2: u8,
    reel3: u8,
    multiplier: u64,
    is_jackpot: bool,
}

// Casino House with separated spin and payout tracking
public struct GameHouse has key {
    id: UID,
    balance: Balance<SUI>,
    owner: address,
    total_spins: u64,
    total_wagered: u64,
    total_payouts: u64,
    jackpot_hits: u64,
    is_active: bool,
    // Track active spins waiting for result processing
    active_spins: Table<u64, ActiveSpin>,
    // Track pending rewards for each player
    pending_rewards: Table<address, vector<PendingReward>>,
    next_spin_id: u64,
}

// Separated Events for different phases
public struct SpinStarted has copy, drop {
    player: address,
    spin_id: u64,
    bet_amount: u64,
    timestamp: u64,
}

public struct SpinResult has copy, drop {
    player: address,
    spin_id: u64,
    reel1: u8,
    reel2: u8,
    reel3: u8,
    timestamp: u64,
}

public struct PayoutCalculated has copy, drop {
    player: address,
    spin_id: u64,
    bet_amount: u64,
    reel1: u8,
    reel2: u8,
    reel3: u8,
    payout: u64,
    multiplier: u64,
    is_jackpot: bool,
    win_type: vector<u8>,
    timestamp: u64,
}

public struct RewardClaimed has copy, drop {
    player: address,
    spin_id: u64,
    amount: u64,
    timestamp: u64,
}

public struct CasinoFunded has copy, drop {
    amount: u64,
    new_balance: u64,
}

// Initialize casino
fun init(ctx: &mut TxContext) {
    let casino = GameHouse {
        id: object::new(ctx),
        balance: balance::zero(),
        owner: ctx.sender(),
        total_spins: 0,
        total_wagered: 0,
        total_payouts: 0,
        jackpot_hits: 0,
        is_active: true,
        active_spins: table::new(ctx),
        pending_rewards: table::new(ctx),
        next_spin_id: 1,
    };
    transfer::share_object(casino);
}

// Fund casino
public entry fun fund_casino(casino: &mut GameHouse, payment: Coin<SUI>) {
    let amount = coin::value(&payment);
    let balance_to_add = coin::into_balance(payment);
    balance::join(&mut casino.balance, balance_to_add);

    event::emit(CasinoFunded {
        amount,
        new_balance: balance::value(&casino.balance),
    });
}

// ========== SYMBOL GENERATION FUNCTIONS ==========

// Generate weighted random symbol with casino-realistic probabilities
entry fun generate_symbol(r: &Random, ctx: &mut TxContext): u8 {
    let mut gen = random::new_generator(r, ctx);
    let roll = random::generate_u16_in_range(&mut gen, 0, 1000);

    // Weighted probability distribution for realistic casino experience
    if (roll < 5) SEVEN // 0.5% chance - Jackpot symbol
    else if (roll < 15) DIAMOND // 1.0% chance - High value
    else if (roll < 35) CROWN // 2.0% chance - High value
    else if (roll < 65) LEAF // 3.0% chance - Medium-high value
    else if (roll < 115) BELL // 5.0% chance - Medium value
    else if (roll < 195) WATERMELON // 8.0% chance - Medium value
    else if (roll < 305) GRAPE // 11.0% chance - Low-medium value
    else if (roll < 455) ORANGE // 15.0% chance - Low value
    else if (roll < 655) LEMON // 20.0% chance - Low value
    else CHERRY // 34.5% chance - Most common
}

// Generate complete spin result with 3 independent reels
entry fun generate_spin_result(r: &Random, ctx: &mut TxContext): (u8, u8, u8) {
    let reel1 = generate_symbol(r, ctx);
    let reel2 = generate_symbol(r, ctx);
    let reel3 = generate_symbol(r, ctx);
    (reel1, reel2, reel3)
}

// ========== SEPARATED SPIN LOGIC ==========

// Step 1: Start spin - only handle bet and generate symbols
entry fun start_spin(
    casino: &mut GameHouse,
    bet_coin: Coin<SUI>,
    random: &Random,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(casino.is_active, EInactiveGame);

    let bet_amount = coin::value(&bet_coin);
    let sender = ctx.sender();
    let current_time = clock::timestamp_ms(clock);

    assert!(bet_amount >= MIN_BET && bet_amount <= MAX_BET, EInvalidBetAmount);

    // Take the bet
    let bet_balance = coin::into_balance(bet_coin);
    balance::join(&mut casino.balance, bet_balance);

    // Generate spin result
    let (reel1, reel2, reel3) = generate_spin_result(random, ctx);

    let spin_id = casino.next_spin_id;
    casino.next_spin_id = casino.next_spin_id + 1;

    // Store active spin for later processing
    let active_spin = ActiveSpin {
        player: sender,
        bet_amount,
        timestamp: current_time,
        reel1,
        reel2,
        reel3,
        is_processed: false,
    };

    table::add(&mut casino.active_spins, spin_id, active_spin);

    // Update basic stats
    casino.total_spins = casino.total_spins + 1;
    casino.total_wagered = casino.total_wagered + bet_amount;

    // Emit spin started event
    event::emit(SpinStarted {
        player: sender,
        spin_id,
        bet_amount,
        timestamp: current_time,
    });

    // Emit spin result event
    event::emit(SpinResult {
        player: sender,
        spin_id,
        reel1,
        reel2,
        reel3,
        timestamp: current_time,
    });
}

// Step 2: Process spin result - calculate payout and handle rewards
public entry fun process_spin_result(
    casino: &mut GameHouse,
    spin_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    let current_time = clock::timestamp_ms(clock);

    assert!(table::contains(&casino.active_spins, spin_id), ENoRewardToClaim);

    let active_spin = table::borrow_mut(&mut casino.active_spins, spin_id);

    // Verify ownership and status
    assert!(active_spin.player == sender, ENotOwner);
    assert!(!active_spin.is_processed, ENoRewardToClaim);

    // Calculate payout
    let (payout, multiplier, is_jackpot, win_type) = calculate_detailed_payout(
        active_spin.reel1,
        active_spin.reel2,
        active_spin.reel3,
        active_spin.bet_amount,
    );

    // Mark as processed
    active_spin.is_processed = true;

    // If there's a payout, add to pending rewards
    if (payout > 0) {
        let reward = PendingReward {
            amount: payout,
            spin_id,
            timestamp: current_time,
            reel1: active_spin.reel1,
            reel2: active_spin.reel2,
            reel3: active_spin.reel3,
            multiplier,
            is_jackpot,
        };

        if (!table::contains(&casino.pending_rewards, sender)) {
            table::add(&mut casino.pending_rewards, sender, vector::empty());
        };

        let player_rewards = table::borrow_mut(&mut casino.pending_rewards, sender);
        vector::push_back(player_rewards, reward);

        if (is_jackpot) {
            casino.jackpot_hits = casino.jackpot_hits + 1;
        };
    };

    // Emit payout calculated event
    event::emit(PayoutCalculated {
        player: sender,
        spin_id,
        bet_amount: active_spin.bet_amount,
        reel1: active_spin.reel1,
        reel2: active_spin.reel2,
        reel3: active_spin.reel3,
        payout,
        multiplier,
        is_jackpot,
        win_type,
        timestamp: current_time,
    });
}

// Combined function for backwards compatibility (optional)
entry fun spin_and_process(
    casino: &mut GameHouse,
    bet_coin: Coin<SUI>,
    random: &Random,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Start spin
    start_spin(casino, bet_coin, random, clock, ctx);

    // Process the latest spin
    let spin_id = casino.next_spin_id - 1;
    process_spin_result(casino, spin_id, clock, ctx);
}

// Claim a specific reward
public entry fun claim_reward(
    casino: &mut GameHouse,
    spin_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    let current_time = clock::timestamp_ms(clock);

    assert!(table::contains(&casino.pending_rewards, sender), ENoRewardToClaim);

    let player_rewards = table::borrow_mut(&mut casino.pending_rewards, sender);
    let mut i = 0;
    let mut found = false;
    let mut reward_amount = 0u64;

    // Find and remove the specific reward
    while (i < vector::length(player_rewards)) {
        let reward = vector::borrow(player_rewards, i);
        if (reward.spin_id == spin_id) {
            // Check if reward hasn't expired
            assert!(current_time <= reward.timestamp + REWARD_EXPIRY_TIME, ERewardExpired);

            reward_amount = reward.amount;
            vector::remove(player_rewards, i);
            found = true;
            break
        };
        i = i + 1;
    };

    assert!(found, ENoRewardToClaim);

    // Clean up empty vector
    if (vector::is_empty(player_rewards)) {
        let empty_vec = table::remove(&mut casino.pending_rewards, sender);
        vector::destroy_empty(empty_vec);
    };

    // Pay out the reward
    assert!(balance::value(&casino.balance) >= reward_amount, EInsufficientBalance);

    let payout_balance = balance::split(&mut casino.balance, reward_amount);
    let payout_coin = coin::from_balance(payout_balance, ctx);
    transfer::public_transfer(payout_coin, sender);

    // Update stats
    casino.total_payouts = casino.total_payouts + reward_amount;

    // Emit claim event
    event::emit(RewardClaimed {
        player: sender,
        spin_id,
        amount: reward_amount,
        timestamp: current_time,
    });
}

// Claim all pending rewards for a player
public entry fun claim_all_rewards(casino: &mut GameHouse, clock: &Clock, ctx: &mut TxContext) {
    let sender = ctx.sender();
    let current_time = clock::timestamp_ms(clock);

    assert!(table::contains(&casino.pending_rewards, sender), ENoRewardToClaim);

    let mut player_rewards = table::remove(&mut casino.pending_rewards, sender);
    let mut total_amount = 0u64;
    let mut i = 0;

    while (i < vector::length(&player_rewards)) {
        let reward = vector::borrow(&player_rewards, i);
        // Only claim non-expired rewards
        if (current_time <= reward.timestamp + REWARD_EXPIRY_TIME) {
            total_amount = total_amount + reward.amount;

            event::emit(RewardClaimed {
                player: sender,
                spin_id: reward.spin_id,
                amount: reward.amount,
                timestamp: current_time,
            });
        };
        i = i + 1;
    };

    if (total_amount > 0) {
        assert!(balance::value(&casino.balance) >= total_amount, EInsufficientBalance);

        let payout_balance = balance::split(&mut casino.balance, total_amount);
        let payout_coin = coin::from_balance(payout_balance, ctx);
        transfer::public_transfer(payout_coin, sender);

        casino.total_payouts = casino.total_payouts + total_amount;
    };

    // Clean up the vector
    while (!vector::is_empty(&player_rewards)) {
        vector::pop_back(&mut player_rewards);
    };
    vector::destroy_empty(player_rewards)
}

// ========== PAYOUT CALCULATION FUNCTIONS ==========

// Check if three symbols match (triple combination)
public fun is_triple_match(reel1: u8, reel2: u8, reel3: u8): bool {
    reel1 == reel2 && reel2 == reel3
}

public fun is_double_match(reel1: u8, reel2: u8, reel3: u8): (bool, u8) {
    if (reel1 == reel2 && reel1 != reel3) {
        (true, reel1)
    } else if (reel1 == reel3 && reel1 != reel2) {
        (true, reel1)
    } else if (reel2 == reel3 && reel2 != reel1) {
        (true, reel2)
    } else {
        (false, 0)
    }
}

// Check if any reel contains a specific symbol
public fun contains_symbol(reel1: u8, reel2: u8, reel3: u8, target_symbol: u8): bool {
    reel1 == target_symbol || reel2 == target_symbol || reel3 == target_symbol
}

// Get multiplier for triple combinations
public fun get_triple_multiplier(symbol: u8): u64 {
    match (symbol) {
        SEVEN => TRIPLE_SEVEN, // 1000x - MEGA JACKPOT!
        DIAMOND => TRIPLE_DIAMOND, // 500x
        CROWN => TRIPLE_CROWN, // 200x
        LEAF => TRIPLE_LEAF, // 100x
        BELL => TRIPLE_BELL, // 50x
        WATERMELON => TRIPLE_WATERMELON, // 25x
        GRAPE => TRIPLE_GRAPE, // 15x
        ORANGE => TRIPLE_ORANGE, // 10x
        LEMON => TRIPLE_LEMON, // 5x
        CHERRY => TRIPLE_CHERRY, // 3x
        _ => 0, // Invalid symbol
    }
}

public fun get_double_multiplier(symbol: u8): u64 {
    match (symbol) {
        SEVEN => DOUBLE_SEVEN,
        DIAMOND => DOUBLE_DIAMOND,
        CROWN => DOUBLE_CROWN,
        LEAF => DOUBLE_LEAF,
        BELL => DOUBLE_BELL,
        WATERMELON => DOUBLE_WATERMELON,
        GRAPE => DOUBLE_GRAPE,
        ORANGE => DOUBLE_ORANGE,
        LEMON => DOUBLE_LEMON,
        CHERRY => DOUBLE_CHERRY,
        _ => 0,
    }
}

// Check for special combinations (non-triple wins)
public fun get_special_multiplier(reel1: u8, reel2: u8, reel3: u8): u64 {
    // Any cherry gives small payout
    if (contains_symbol(reel1, reel2, reel3, SEVEN)) {
        SEVEN_LINE // 2x multiplier
    } else if (contains_symbol(reel1, reel2, reel3, CHERRY)) {
        CHERRY_LINE // 1x multiplier
    } else {
        0 // No special combination
    }
}

// Determine if result is a jackpot
public fun is_jackpot_win(reel1: u8, reel2: u8, reel3: u8): bool {
    reel1 == SEVEN && reel2 == SEVEN && reel3 == SEVEN
}

// Main payout calculation function
public fun calculate_payout(reel1: u8, reel2: u8, reel3: u8, bet_amount: u64): (u64, u64, bool) {
    if (is_triple_match(reel1, reel2, reel3)) {
        let multiplier = get_triple_multiplier(reel1);
        let payout = bet_amount * multiplier;
        let is_jackpot = is_jackpot_win(reel1, reel2, reel3);
        (payout, multiplier, is_jackpot)
    } else {
        let (is_double, symbol) = is_double_match(reel1, reel2, reel3);
        if (is_double) {
            let multiplier = get_double_multiplier(symbol);
            let payout = bet_amount * multiplier / 100; // multiplier: 1.1x = 110
            (payout, multiplier, false)
        } else {
            let multiplier = get_special_multiplier(reel1, reel2, reel3);
            let payout = bet_amount * multiplier;
            (payout, multiplier, false)
        }
    }
}

// Advanced payout calculation with detailed breakdown
public fun calculate_detailed_payout(
    reel1: u8,
    reel2: u8,
    reel3: u8,
    bet_amount: u64,
): (u64, u64, bool, vector<u8>) {
    let (payout, multiplier, is_jackpot) = calculate_payout(reel1, reel2, reel3, bet_amount);

    // Generate win description
    let win_type = if (is_jackpot) {
        b"MEGA JACKPOT!"
    } else if (is_triple_match(reel1, reel2, reel3)) {
        b"TRIPLE MATCH"
    } else {
        let (is_double, _) = is_double_match(reel1, reel2, reel3);
        if (is_double) {
            b"DOUBLE MATCH"
        } else if (multiplier > 0) {
            b"SPECIAL WIN"
        } else {
            b"NO WIN"
        }
    };

    (payout, multiplier, is_jackpot, win_type)
}

// ========== VIEW FUNCTIONS FOR ACTIVE SPINS ==========

// Get active spin details
public fun get_active_spin(casino: &GameHouse, spin_id: u64): ActiveSpin {
    assert!(table::contains(&casino.active_spins, spin_id), ENoRewardToClaim);
    *table::borrow(&casino.active_spins, spin_id)
}

// Get all unprocessed spins for a player
public fun get_player_unprocessed_spins(casino: &GameHouse, player: address): vector<u64> {
    let mut unprocessed_spins = vector::empty<u64>();
    let mut spin_id = 1u64;

    while (spin_id < casino.next_spin_id) {
        if (table::contains(&casino.active_spins, spin_id)) {
            let active_spin = table::borrow(&casino.active_spins, spin_id);
            if (active_spin.player == player && !active_spin.is_processed) {
                vector::push_back(&mut unprocessed_spins, spin_id);
            };
        };
        spin_id = spin_id + 1;
    };

    unprocessed_spins
}

// Check if spin can be processed
public fun can_process_spin(casino: &GameHouse, spin_id: u64, player: address): bool {
    if (!table::contains(&casino.active_spins, spin_id)) {
        return false
    };

    let active_spin = table::borrow(&casino.active_spins, spin_id);
    active_spin.player == player && !active_spin.is_processed
}

// Clean up old processed spins (for gas optimization)
public entry fun cleanup_processed_spins(
    casino: &mut GameHouse,
    spin_ids: vector<u64>,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == casino.owner, ENotOwner);

    let mut i = 0;
    while (i < vector::length(&spin_ids)) {
        let spin_id = *vector::borrow(&spin_ids, i);
        if (table::contains(&casino.active_spins, spin_id)) {
            let active_spin = table::borrow(&casino.active_spins, spin_id);
            if (active_spin.is_processed) {
                table::remove(&mut casino.active_spins, spin_id);
            };
        };
        i = i + 1;
    };
}

public fun get_pending_rewards(casino: &GameHouse, player: address): vector<PendingReward> {
    if (table::contains(&casino.pending_rewards, player)) {
        *table::borrow(&casino.pending_rewards, player)
    } else {
        vector::empty()
    }
}

// View function to get total pending reward amount for a player
public fun get_total_pending_amount(casino: &GameHouse, player: address): u64 {
    if (!table::contains(&casino.pending_rewards, player)) {
        return 0
    };

    let rewards = table::borrow(&casino.pending_rewards, player);
    let mut total = 0u64;
    let mut i = 0;

    while (i < vector::length(rewards)) {
        let reward = vector::borrow(rewards, i);
        total = total + reward.amount;
        i = i + 1;
    };

    total
}

// ========== ADDITIONAL VIEW FUNCTIONS ==========

// Get symbol probabilities for transparency
public fun get_symbol_probabilities(): vector<u64> {
    vector[
        345, // CHERRY - 34.5%
        200, // LEMON - 20.0%
        150, // ORANGE - 15.0%
        110, // GRAPE - 11.0%
        80, // WATERMELON - 8.0%
        50, // BELL - 5.0%
        30, // LEAF - 3.0%
        20, // CROWN - 2.0%
        10, // DIAMOND - 1.0%
        5, // SEVEN - 0.5%
    ]
}

public fun get_casino_stats(casino: &GameHouse): (u64, u64, u64, u64, u64, bool) {
    (
        balance::value(&casino.balance),
        casino.total_spins,
        casino.total_wagered,
        casino.total_payouts,
        casino.jackpot_hits,
        casino.is_active,
    )
}

public fun get_bet_limits(): (u64, u64) {
    (MIN_BET, MAX_BET)
}

public fun get_triple_payout_table(): vector<u64> {
    vector[
        TRIPLE_SEVEN,
        TRIPLE_DIAMOND,
        TRIPLE_CROWN,
        TRIPLE_LEAF,
        TRIPLE_BELL,
        TRIPLE_WATERMELON,
        TRIPLE_GRAPE,
        TRIPLE_ORANGE,
        TRIPLE_LEMON,
        TRIPLE_CHERRY,
    ]
}

public fun get_double_payout_table(): vector<u64> {
    vector[
        DOUBLE_SEVEN,
        DOUBLE_DIAMOND,
        DOUBLE_CROWN,
        DOUBLE_LEAF,
        DOUBLE_BELL,
        DOUBLE_WATERMELON,
        DOUBLE_GRAPE,
        DOUBLE_ORANGE,
        DOUBLE_LEMON,
        DOUBLE_CHERRY,
    ]
}

public fun get_symbol_name(symbol: u8): vector<u8> {
    if (symbol == CHERRY) b"CHERRY"
    else if (symbol == LEMON) b"LEMON"
    else if (symbol == ORANGE) b"ORANGE"
    else if (symbol == GRAPE) b"GRAPE"
    else if (symbol == WATERMELON) b"WATERMELON"
    else if (symbol == DIAMOND) b"DIAMOND"
    else if (symbol == SEVEN) b"SEVEN"
    else if (symbol == BELL) b"BELL"
    else if (symbol == LEAF) b"LEAF"
    else if (symbol == CROWN) b"CROWN"
    else b"UNKNOWN"
}

// Management functions remain the same
public entry fun withdraw_casino_funds(casino: &mut GameHouse, amount: u64, ctx: &mut TxContext) {
    assert!(ctx.sender() == casino.owner, ENotOwner);
    assert!(balance::value(&casino.balance) >= amount, EInsufficientBalance);

    let withdrawal = balance::split(&mut casino.balance, amount);
    let coin = coin::from_balance(withdrawal, ctx);
    transfer::public_transfer(coin, casino.owner);
}

public entry fun toggle_casino_status(casino: &mut GameHouse, ctx: &TxContext) {
    assert!(ctx.sender() == casino.owner, ENotOwner);
    casino.is_active = !casino.is_active;
}

public entry fun transfer_casino_ownership(
    casino: &mut GameHouse,
    new_owner: address,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == casino.owner, ENotOwner);
    casino.owner = new_owner;
}

public entry fun emergency_shutdown(casino: &mut GameHouse, ctx: &TxContext) {
    assert!(ctx.sender() == casino.owner, ENotOwner);
    casino.is_active = false;
}
