# @version 0.3.7

# Constants
REVEAL_FEE: constant(uint256) = 10**16  # 0.01 ETH (or testnet equivalent) to reveal the punchline
MAX_GUESSES: constant(uint256) = 3      # Maximum free guesses per user per joke

# Joke structure with a mediaURI field to reference an IPFS hash or URL.
struct Joke:
    punchline: String[256]       # The full punchline text
    punchlineHash: bytes32       # keccak256 hash of the punchline (used for validation)
    mediaURI: String[256]        # IPFS hash or URL for the associated video/photo
    prizePool: uint256           # Accumulated funds from reveal fees
    answered: bool               # True if someone guessed correctly

# Mappings to store jokes and track per-user interactions.
jokes: public(HashMap[uint256, Joke])
guesses: public(HashMap[uint256, HashMap[address, uint256]])
revealed: public(HashMap[uint256, HashMap[address, bool]])

# Contract owner (administrator)
owner: public(address)

# ------------------- Events -------------------

event JokeAdded:
    jokeId: uint256

event CorrectGuess:
    jokeId: uint256
    user: address

event IncorrectGuess:
    jokeId: uint256
    user: address
    attempt: uint256

event PunchlineRevealed:
    jokeId: uint256
    user: address
    punchline: String[256]

# ------------------- Constructor -------------------

@external
def __init__():
    self.owner = msg.sender

# ------------------- Admin Functions -------------------

@external
def addJoke(jokeId: uint256, punchline: String[256], mediaURI: String[256]):
    """
    Adds a new joke to the contract.
    Only the owner may add jokes.
    - jokeId: A unique identifier for the joke.
    - punchline: The punchline text (its keccak256 hash is stored for later validation).
    - mediaURI: An IPFS hash or URL pointing to the joke's associated video/photo.
    """
    # Only the contract owner may add jokes.
    assert msg.sender == self.owner, "Only owner can add jokes"
    # Ensure the joke doesn't already exist (check that its hash is empty).
    assert self.jokes[jokeId].punchlineHash == empty(bytes32), "Joke already exists"
    
    punchline_hash: bytes32 = keccak256(convert(punchline, Bytes[256]))
    
    self.jokes[jokeId] = Joke({
        punchline: punchline,
        punchlineHash: punchline_hash,
        mediaURI: mediaURI,
        prizePool: 0,
        answered: False
    })
    
    log JokeAdded(jokeId)

# ------------------- User Functions -------------------

@external
def guessPunchline(jokeId: uint256, guess: String[256]):
    """
    Allows a user to guess the punchline for a joke for free.
    - The joke must exist and not be already answered.
    - Each user is allowed up to MAX_GUESSES attempts.
    - If the keccak256 hash of the provided guess matches the stored hash,
      the joke is marked as answered and a CorrectGuess event is logged.
    - Otherwise, an IncorrectGuess event is logged.
    """
    joke: Joke = self.jokes[jokeId]
    assert joke.punchlineHash != empty(bytes32), "Joke does not exist"
    assert not joke.answered, "Joke already answered"
    
    user_attempts: uint256 = self.guesses[jokeId][msg.sender]
    # Ensure the user has not exceeded the maximum free guesses.
    assert user_attempts < MAX_GUESSES, "No guesses remaining; please pay to reveal the punchline"
    
    # Record the guess.
    self.guesses[jokeId][msg.sender] = user_attempts + 1
    
    guess_hash: bytes32 = keccak256(convert(guess, Bytes[256]))
    if guess_hash == joke.punchlineHash:
        self.jokes[jokeId].answered = True
        log CorrectGuess(jokeId, msg.sender)
    else:
        log IncorrectGuess(jokeId, msg.sender, self.guesses[jokeId][msg.sender])

@external
@payable
def revealPunchline(jokeId: uint256) -> String[256]:
    """
    Allows a user to pay to reveal the punchline after using up free guesses.
    - The user must have already made at least MAX_GUESSES attempts.
    - The call must send exactly REVEAL_FEE.
    - The fee is added to the joke's prizePool.
    - The function returns the punchline and logs the reveal event.
    """
    joke: Joke = self.jokes[jokeId]
    assert joke.punchlineHash != empty(bytes32), "Joke does not exist"
    # Ensure the user has exhausted their free guesses.
    assert self.guesses[jokeId][msg.sender] >= MAX_GUESSES, "Guesses remaining; cannot reveal yet"
    # Prevent multiple reveals by the same user.
    assert not self.revealed[jokeId][msg.sender], "Punchline already revealed"
    assert msg.value == REVEAL_FEE, "Incorrect reveal fee"
    
    self.jokes[jokeId].prizePool += msg.value
    self.revealed[jokeId][msg.sender] = True
    log PunchlineRevealed(jokeId, msg.sender, joke.punchline)
    return joke.punchline

# ------------------- Withdrawal -------------------

@external
def withdraw():
    """
    Allows the contract owner to withdraw the entire balance held in the contract.
    """
    assert msg.sender == self.owner, "Only owner can withdraw"
    send(self.owner, self.balance)