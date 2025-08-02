"use client";

import {
    fromSuiU64,
    useJackpotBalance,
    useSpinSlot,
} from "@/hooks/useSlotMachineContract";
import { useState, useRef, useEffect } from "react";

const SYMBOLS: string[] = [
    "🍒",
    "🍋",
    "🍊",
    "🍇",
    "🍉",
    "💎",
    "7️⃣",
    "🔔",
    "🍀",
    "👑",
];

const REEL_COUNT = 3;

// Bet amounts
const betAmounts = [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0];

// Create a list of symbol strings for a reel
const createReelSymbols = (symbols: string[], count = 30): string[] => {
    const reelContent: string[] = [];
    for (let i = 0; i < count; i++) {
        const sym = symbols[Math.floor(Math.random() * symbols.length)];
        reelContent.push(sym);
    }
    return reelContent;
};

const SlotMachine = () => {
    const [showWinFlash, setShowWinFlash] = useState(false);
    const [winMessage, setWinMessage] = useState<string>("");
    const [isSpinning, setIsSpinning] = useState<boolean>(false);
    const [bet, setBet] = useState(0.001);

    const { spinSlot, spinResult } = useSpinSlot();
    const jackpotBalance = useJackpotBalance();

    // State to hold the symbols for each reel
    const [reelSymbols, setReelSymbols] = useState<string[][]>([
        ["🍒"],
        ["🍒"],
        ["🍒"],
    ]);

    // State to manage the CSS transform for the animation
    const [reelTransforms, setReelTransforms] = useState<string[]>(
        Array(REEL_COUNT).fill("translateY(0)")
    );

    const spinResultsRef = useRef<string[]>([]);
    const timeoutRefs = useRef<NodeJS.Timeout[]>([]);

    // Cleanup function for timeouts
    useEffect(() => {
        return () => {
            timeoutRefs.current.forEach(clearTimeout);
        };
    }, []);

    const animateSpinWithResult = (resultSymbols: string[]) => {
        if (isSpinning) return;

        setIsSpinning(true);
        setWinMessage("");
        spinResultsRef.current = [];

        // Clear any previous timeouts
        timeoutRefs.current.forEach(clearTimeout);
        timeoutRefs.current = [];

        const newReelSymbols: string[][] = [];
        for (let i = 0; i < REEL_COUNT; i++) {
            const randomSymbols = createReelSymbols(SYMBOLS);
            const resultSymbol = resultSymbols[i];
            const finalSymbols = [...randomSymbols, resultSymbol];
            newReelSymbols.push(finalSymbols);
        }

        setReelSymbols(newReelSymbols);

        // This ensures the animation resets before starting a new one.
        // By setting the transform to 0 and then a new value, we force a transition.
        setReelTransforms(Array(REEL_COUNT).fill("translateY(0)"));

        newReelSymbols.forEach((symbols, i) => {
            const targetIndex = symbols.length - 1;
            const translateY = -targetIndex * 100;

            const timeout = setTimeout(() => {
                setReelTransforms((prevTransforms) => {
                    const newTransforms = [...prevTransforms];
                    newTransforms[i] = `translateY(${translateY}px)`;
                    return newTransforms;
                });

                // Store the result of the spin
                spinResultsRef.current[i] = symbols[targetIndex];

                // Check for win after the last reel has finished spinning
                if (i === REEL_COUNT - 1) {
                    timeoutRefs.current.push(
                        setTimeout(() => {
                            const results = spinResultsRef.current;
                            if (results.every((s) => s === results[0])) {
                                setWinMessage("🎉 You win!");
                            } else {
                                setWinMessage("❌ Try again!");
                            }
                            setIsSpinning(false);
                        }, 1000)
                    );
                }
            }, i * 400); // Each reel stops a bit later

            timeoutRefs.current.push(timeout);
        });
    };

    const handleSpinClick = async () => {
        await spinSlot(0.1);
    };

    useEffect(() => {
        if (
            spinResult &&
            spinResult.reel1 &&
            spinResult.reel2 &&
            spinResult.reel3
        ) {
            const symbols = [
                SYMBOLS[parseInt(spinResult.reel1)],
                SYMBOLS[parseInt(spinResult.reel2)],
                SYMBOLS[parseInt(spinResult.reel3)],
            ];

            console.log(symbols);
            animateSpinWithResult(symbols);
        }
    }, [spinResult]);

    return (
        <div className="flex items-center justify-center p-4">
            <div className="relative">
                <div className="bg-gradient-to-br from-gray-800 to-gray-900 rounded-3xl p-8 shadow-2xl border-4 border-cyan-400 relative overflow-hidden">
                    <div className="absolute inset-0 bg-gradient-to-br from-transparent via-white/5 to-transparent"></div>

                    {/* Jackpot Header */}
                    <div className="bg-gradient-to-r from-cyan-400 to-purple-500 rounded-2xl p-4 mb-6 border-2 border-cyan-300 shadow-lg">
                        <div className="text-center">
                            <div className="text-2xl font-bold text-white tracking-wider">
                                JACKPOT:
                                {jackpotBalance !== null
                                    ? ` ${fromSuiU64(jackpotBalance)} SUI`
                                    : " LOADING JACKPOT..."}
                            </div>
                        </div>
                    </div>

                    {/* Credits and Win Panel */}
                    <div className="bg-black rounded-xl p-4 mb-6 border-2 border-gray-600">
                        <div className="grid grid-cols-2 gap-4 text-center">
                            <div>
                                <div className="text-cyan-300 text-sm font-bold tracking-wider">
                                    BALANCE
                                </div>
                                <div className="text-cyan-200 text-2xl font-mono bg-black/50 rounded px-2">
                                    0
                                </div>
                            </div>
                            <div>
                                <div className="text-cyan-300 text-sm font-bold tracking-wider">
                                    WIN
                                </div>
                                <div
                                    className={`text-2xl font-mono bg-black/50 rounded px-2 ${
                                        showWinFlash
                                            ? "text-purple-400 animate-pulse"
                                            : "text-cyan-200"
                                    }`}
                                >
                                    0
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* Slot Machine Reel Window */}
                    <div className="relative">
                        {/* Game UI */}
                        <div
                            className="flex flex-col items-center text-white shadow-[0_0_40px_#ff0] rounded-lg"
                            style={{
                                background:
                                    "radial-gradient(circle at center, #111 0%, #000 100%)",
                            }}
                        >
                            <div className="relative px-10 py-8 flex gap-5">
                                {reelSymbols.map((symbols, i) => (
                                    <div
                                        key={i}
                                        className="w-25 h-25 bg-white border-4 border-[#444] overflow-hidden rounded-lg shadow-[inset_0_0_10px_#000]"
                                    >
                                        <div
                                            className="flex flex-col transition-transform duration-1000 ease-out"
                                            style={{
                                                transform: reelTransforms[i],
                                            }}
                                        >
                                            {symbols.map(
                                                (symbol, symbolIndex) => (
                                                    <div
                                                        key={symbolIndex}
                                                        className="h-25 flex justify-center items-center text-5xl/25"
                                                    >
                                                        {symbol}
                                                    </div>
                                                )
                                            )}
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>

                        {/* Lights */}
                        <div className="absolute top-2 left-2 w-3 h-3 bg-purple-400 rounded-full animate-pulse"></div>
                        <div className="absolute top-2 right-2 w-3 h-3 bg-cyan-400 rounded-full animate-pulse delay-500"></div>
                        <div className="absolute bottom-2 left-2 w-3 h-3 bg-yellow-300 rounded-full animate-pulse delay-1000"></div>
                        <div className="absolute bottom-2 right-2 w-3 h-3 bg-rose-500 rounded-full animate-pulse delay-1500"></div>
                    </div>

                    {/* Bet Amount */}
                    <div className="mt-6">
                        <label className="block text-sm text-gray-300 font-semibold mb-2">
                            Bet Amount:
                        </label>
                        <div className="flex justify-center gap-2">
                            {betAmounts.map((amount) => (
                                <button
                                    key={amount}
                                    onClick={() => setBet(amount)}
                                    className={`
                          relative px-3 py-2 rounded-lg text-sm font-semibold cursor-pointer text-white
                          ${
                              bet === amount
                                  ? "bg-gradient-to-br from-violet-400 to-sky-500"
                                  : "bg-white/10 hover:bg-white/20"
                          }
                        `}
                                >
                                    {amount} SUI
                                </button>
                            ))}
                        </div>
                    </div>

                    {/* Spin Button */}
                    <div className="mt-4 text-center">
                        <button
                            className={`relative bg-gradient-to-r from-cyan-400 to-purple-500 text-white font-bold text-lg rounded-xl p-4 shadow-md border border-cyan-300 transform transition-all duration-150 ${
                                isSpinning
                                    ? "opacity-50 cursor-not-allowed"
                                    : "hover:scale-105 active:scale-95 shadow-cyan-500/50 cursor-pointer"
                            }`}
                            onClick={handleSpinClick}
                            disabled={isSpinning}
                        >
                            <div className="absolute inset-0 bg-gradient-to-t from-transparent to-white/10 rounded-lg"></div>
                            <div className="relative min-w-26">
                                {isSpinning ? "SPINNING..." : "SPIN"}
                            </div>
                        </button>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default SlotMachine;
