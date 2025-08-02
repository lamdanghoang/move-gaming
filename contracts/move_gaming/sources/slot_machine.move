module move_gaming::slot_machine;

use sui::balance::{Self, Balance};
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

// Game constants
const MIN_BET: u64 = 100000; // 0.0001 SUI (100,000 MIST)
const MAX_BET: u64 = 10000000000; // 10 SUI
// const HOUSE_EDGE: u64 = 8; // 8% house edge (typical for casino slots)

// Slot symbols (1-10, with 7 being the jackpot symbol)
const CHERRY: u8 = 0; // 🍒
const LEMON: u8 = 1; // 🍋
const ORANGE: u8 = 2; // 🍊
const GRAPE: u8 = 3; // 🍇
const WATERMELON: u8 = 4; // 🍉
const DIAMOND: u8 = 5; // 💎
const SEVEN: u8 = 6; // 777 (Jackpot)
const BELL: u8 = 7; // 🔔
const LEAF: u8 = 8; // 🍀
const CROWN: u8 = 9; // 👑

// Payout table (multipliers)
const TRIPLE_SEVEN: u64 = 1000; // 1000x - MEGA JACKPOT!
const TRIPLE_DIAMOND: u64 = 500; // 500x
const TRIPLE_CROWN: u64 = 200;
const TRIPLE_LEAF: u64 = 100;
const TRIPLE_BELL: u64 = 50;
const TRIPLE_WATERMELON: u64 = 25;
const TRIPLE_GRAPE: u64 = 15;
const TRIPLE_ORANGE: u64 = 10;
const TRIPLE_LEMON: u64 = 5;
const TRIPLE_CHERRY: u64 = 3;

const SEVEN_LINE: u64 = 2;

// Main Casino House
public struct GameHouse has key {
    id: UID,
    balance: Balance<SUI>,
    owner: address,
    total_spins: u64,
    total_wagered: u64,
    total_payouts: u64,
    jackpot_hits: u64,
    is_active: bool,
    payout: Table<address, u64>,
    player_books: Table<address, ID>,
}

// Events
public struct CasinoFunded has copy, drop {
    amount: u64,
    new_balance: u64,
}

public struct SpinResult has copy, drop, store {
    player: address,
    bet_amount: u64,
    reel1: u8,
    reel2: u8,
    reel3: u8,
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
        payout: table::new<address, u64>(ctx),
        player_books: table::new<address, ID>(ctx),
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

// Generate weighted random symbol (7s are rarer)
entry fun generate_symbol(r: &Random, ctx: &mut TxContext): u8 {
    let mut gen = random::new_generator(r, ctx);
    let roll = random::generate_u16_in_range(&mut gen, 0, 1000);

    // Weighted probability for casino realism
    if (roll < 5) SEVEN // 0.5% chance
    else if (roll < 15) DIAMOND // 1.0% chance
    else if (roll < 35) CROWN // 2.0% chance
    else if (roll < 65) LEAF // 3.0% chance
    else if (roll < 115) BELL // 5.0% chance
    else if (roll < 195) WATERMELON // 8.0% chance
    else if (roll < 305) GRAPE // 11.0% chance
    else if (roll < 455) ORANGE // 15.0% chance
    else if (roll < 655) LEMON // 20.0% chance
    else CHERRY // 34.5% chance
}

// Generate 3 symbols
fun generate_symbols(r: &Random, ctx: &mut TxContext): (u8, u8, u8) {
    let reel1 = generate_symbol(r, ctx);
    let reel2 = generate_symbol(r, ctx);
    let reel3 = generate_symbol(r, ctx);
    (reel1, reel2, reel3)
}

// Entry function to spin the slot machine — frontend calls this
entry fun spin_slot(
    house: &mut GameHouse,
    bet_coin: Coin<SUI>,
    random: &Random,
    ctx: &mut TxContext,
) {
    assert!(house.is_active, EInactiveGame);

    let bet_amount = coin::value(&bet_coin);
    let sender = ctx.sender();

    assert!(bet_amount >= MIN_BET && bet_amount <= MAX_BET, EInvalidBetAmount);

    let bet_balance = coin::into_balance(bet_coin);
    balance::join(&mut house.balance, bet_balance);

    // Generate spin result
    let (reel1, reel2, reel3) = generate_symbols(random, ctx);

    // Update basic stats
    house.total_spins = house.total_spins + 1;
    house.total_wagered = house.total_wagered + bet_amount;

    event::emit(SpinResult {
        player: sender,
        bet_amount,
        reel1,
        reel2,
        reel3,
    });
}

// Check winning combinations and calculate payout
public fun calculate_payout(reel1: u8, reel2: u8, reel3: u8, bet_amount: u64): (u64, u64, bool) {
    let multiplier = if (reel1 == reel2 && reel2 == reel3) {
        match (reel1) {
            SEVEN => TRIPLE_SEVEN,
            DIAMOND => TRIPLE_DIAMOND,
            CROWN => TRIPLE_CROWN,
            LEAF => TRIPLE_LEAF,
            BELL => TRIPLE_BELL,
            WATERMELON => TRIPLE_WATERMELON,
            GRAPE => TRIPLE_GRAPE,
            ORANGE => TRIPLE_ORANGE,
            LEMON => TRIPLE_LEMON,
            CHERRY => TRIPLE_CHERRY,
            _ => 0,
        }
    } else if (reel1 == CHERRY || reel2 == CHERRY || reel3 == CHERRY) {
        SEVEN_LINE
    } else {
        0
    };

    let payout = bet_amount * multiplier;
    let is_jackpot = (reel1 == SEVEN && reel2 == SEVEN && reel3 == SEVEN);
    (payout, multiplier, is_jackpot)
}

// View functions
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

public fun get_payout_table(): vector<u64> {
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

// Casino management functions
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

// Emergency functions
public entry fun emergency_shutdown(casino: &mut GameHouse, ctx: &TxContext) {
    assert!(ctx.sender() == casino.owner, ENotOwner);
    casino.is_active = false;
}
