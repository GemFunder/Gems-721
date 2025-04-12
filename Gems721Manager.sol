// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { Utils } from './Utils.sol';
import { SVGRenderer } from './SVGRenderer.sol';

/**
 * @title MultiPartyHandshake
 * @dev A helper contract that manages multi-party commit-reveal schemes
 */
contract MultiPartyHandshake {
    // Mapping to store commitment hashes for each handshake
    mapping(bytes32 => mapping(address => bytes32)) public commitments;
    
    // Mapping to store revealed secrets for each handshake
    mapping(bytes32 => mapping(address => bytes32)) public reveals;
    
    // Mapping to track participants for each handshake
    mapping(bytes32 => address[]) public participants;
    
    // Mapping to track required participants for each handshake
    mapping(bytes32 => uint256) public requiredParticipants;
    
    // Mapping to check if a handshake is complete
    mapping(bytes32 => bool) public handshakeComplete;
    
    // Events
    event HandshakeCreated(bytes32 indexed handshakeId, uint256 requiredParticipants);
    event CommitmentSubmitted(bytes32 indexed handshakeId, address participant);
    event SecretRevealed(bytes32 indexed handshakeId, address participant, bytes32 secret);
    event HandshakeCompleted(bytes32 indexed handshakeId, bytes32 combinedEntropy);
    
    /**
     * @dev Creates a new handshake for entropy generation
     * @param handshakeId Unique identifier for the handshake
     * @param minParticipants Minimum participants required
     */
    function createHandshake(bytes32 handshakeId, uint256 minParticipants) internal {
        require(minParticipants > 0, "Must require at least 1 participant");
        require(participants[handshakeId].length == 0, "Handshake already exists");
        
        requiredParticipants[handshakeId] = minParticipants;
        emit HandshakeCreated(handshakeId, minParticipants);
    }
    
    /**
     * @dev Submit a commitment (hash of secret) to a handshake
     * @param handshakeId Unique identifier for the handshake
     * @param commitment Hash of the participant's secret
     */
    function submitCommitment(bytes32 handshakeId, bytes32 commitment) external {
        require(requiredParticipants[handshakeId] > 0, "Handshake does not exist");
        require(commitments[handshakeId][msg.sender] == bytes32(0), "Already committed");
        require(!handshakeComplete[handshakeId], "Handshake already complete");
        
        commitments[handshakeId][msg.sender] = commitment;
        participants[handshakeId].push(msg.sender);
        
        emit CommitmentSubmitted(handshakeId, msg.sender);
    }
    
    /**
     * @dev Reveal a previously committed secret
     * @param handshakeId Unique identifier for the handshake
     * @param secret The secret value that was hashed in the commitment
     */
    function revealSecret(bytes32 handshakeId, bytes32 secret) external {
        require(commitments[handshakeId][msg.sender] != bytes32(0), "No commitment found");
        require(reveals[handshakeId][msg.sender] == bytes32(0), "Already revealed");
        require(!handshakeComplete[handshakeId], "Handshake already complete");
        
        // Verify the commitment matches the secret
        require(keccak256(abi.encodePacked(secret, msg.sender)) == commitments[handshakeId][msg.sender], 
                "Secret does not match commitment");
        
        reveals[handshakeId][msg.sender] = secret;
        emit SecretRevealed(handshakeId, msg.sender, secret);
        
        // Check if we have enough reveals to complete the handshake
        checkAndFinalizeHandshake(handshakeId);
    }
    
    /**
     * @dev Check if handshake has enough reveals and finalize if so
     * @param handshakeId Unique identifier for the handshake
     * @return Combined entropy if handshake is complete, or zero bytes32 if not
     */
    function checkAndFinalizeHandshake(bytes32 handshakeId) internal returns (bytes32) {
        uint256 revealCount = 0;
        address[] memory handshakeParticipants = participants[handshakeId];
        
        // Count valid reveals
        for (uint i = 0; i < handshakeParticipants.length; i++) {
            if (reveals[handshakeId][handshakeParticipants[i]] != bytes32(0)) {
                revealCount++;
            }
        }
        
        // If we have enough reveals, combine them to generate entropy
        if (revealCount >= requiredParticipants[handshakeId]) {
            bytes32 combinedEntropy = bytes32(0);
            
            // XOR all revealed secrets together
            for (uint i = 0; i < handshakeParticipants.length; i++) {
                address participant = handshakeParticipants[i];
                if (reveals[handshakeId][participant] != bytes32(0)) {
                    combinedEntropy = combinedEntropy ^ reveals[handshakeId][participant];
                }
            }
            
            // Add blockchain state information for additional entropy
            combinedEntropy = keccak256(abi.encodePacked(
                combinedEntropy,
                blockhash(block.number - 1),
                block.timestamp,
                block.prevrandao
            ));
            
            handshakeComplete[handshakeId] = true;
            emit HandshakeCompleted(handshakeId, combinedEntropy);
            return combinedEntropy;
        }
        
        return bytes32(0);
    }
    
    /**
     * @dev Check if a handshake is ready to be completed
     * @param handshakeId Unique identifier for the handshake
     * @return Boolean indicating if handshake is ready
     */
    function isHandshakeReady(bytes32 handshakeId) public view returns (bool) {
        if (handshakeComplete[handshakeId]) {
            return false; // Already complete
        }
        
        uint256 revealCount = 0;
        address[] memory handshakeParticipants = participants[handshakeId];
        
        for (uint i = 0; i < handshakeParticipants.length; i++) {
            if (reveals[handshakeId][handshakeParticipants[i]] != bytes32(0)) {
                revealCount++;
            }
        }
        
        return revealCount >= requiredParticipants[handshakeId];
    }
    
    /**
     * @dev Get the entropy from a completed handshake
     * @param handshakeId Unique identifier for the handshake
     * @return The combined entropy from all participants
     */
    function getHandshakeEntropy(bytes32 handshakeId) public view returns (bytes32) {
        require(handshakeComplete[handshakeId], "Handshake not complete");
        
        bytes32 combinedEntropy = bytes32(0);
        address[] memory handshakeParticipants = participants[handshakeId];
        
        // Recalculate the combined entropy (same algorithm as in checkAndFinalizeHandshake)
        for (uint i = 0; i < handshakeParticipants.length; i++) {
            address participant = handshakeParticipants[i];
            if (reveals[handshakeId][participant] != bytes32(0)) {
                combinedEntropy = combinedEntropy ^ reveals[handshakeId][participant];
            }
        }
        
        return keccak256(abi.encodePacked(
            combinedEntropy,
            blockhash(block.number - 1),
            block.timestamp,
            block.prevrandao
        ));
    }
}

contract NFTManager is ERC721, ERC721Enumerable, Ownable, MultiPartyHandshake {
    uint256 private _nextTokenId;
    
    uint256 public constant PRICE = 0.01 ether;
    uint256 public constant MAX_NFT_ITEMS = 777;
    SVGRenderer public renderer;
    
    // Randomness and reveal state variables
    bool public revealActive = false;
    bytes32 public collectionEntropyHandshake;
    mapping(uint256 => bytes32) public tokenRandomSeeds;
    
    // Handshake parameters
    uint256 public constant MIN_HANDSHAKE_PARTICIPANTS = 3;
    
    // Funding distribution
    struct FundCommitment {
        bytes32 commitment;       // Hash of the user's funding allocation secret
        bytes32 revealedSecret;   // The revealed secret (only set after reveal)
        bool revealed;            // Whether the secret has been revealed
        uint256 amount;           // Amount of ETH committed
        uint256 timestamp;        // When the commitment was made
    }
    
    // Fund distributions
    struct FundDistribution {
        address recipient;        // Recipient address
        uint256 percentage;       // Percentage of funds (out of 10000, so 5000 = 50%)
        bool isFixed;             // If true, uses fixed percentage; if false, uses random percentage
    }
    
    // Mapping for fund commitments
    mapping(address => FundCommitment) public fundCommitments;
    
    // Fund distribution recipients (address => percentage, using basis points: 10000 = 100%)
    FundDistribution[] public fundDistributions;
    
    // Total fixed percentage allocations (should not exceed 5000 = 50%)
    uint256 public totalFixedAllocation;
    
    // Treasury address for collecting fees
    address public treasuryAddress;
    
    // Mint phases
    enum MintPhase { CLOSED, PREMINT, PUBLIC, REVEAL }
    MintPhase public currentPhase = MintPhase.CLOSED;
    
    // Events
    event MintPhaseChanged(MintPhase newPhase);
    event TokenRandomnessAssigned(uint256 indexed tokenId, bytes32 randomSeed);
    event RevealActivated();
    event FundCommitmentCreated(address indexed user, bytes32 commitment, uint256 amount);
    event FundSecretRevealed(address indexed user, bytes32 secret);
    event FundsDistributed(address indexed from, uint256 amount);
    event DistributionUpdated(address indexed recipient, uint256 percentage, bool isFixed);
    
    constructor(uint256 _reservedForTeam, address _treasuryAddress) ERC721("Gems Alpha v1", "GEMS") Ownable(msg.sender) {
        renderer = new SVGRenderer();
        treasuryAddress = _treasuryAddress;
        
        // Start in premint phase
        currentPhase = MintPhase.PREMINT;
        emit MintPhaseChanged(MintPhase.PREMINT);
        
        // Set up default fund distributions (can be updated by owner)
        // Initial distribution: 25% fixed to treasury, 25% random distribution among participants
        addFundDistribution(_treasuryAddress, 2500, true);  // 25% fixed to treasury
        
        // Reserve team NFTs
        for (uint i=0; i < _reservedForTeam; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
        }
        
        // Create initial entropy handshake for the collection
        collectionEntropyHandshake = keccak256(abi.encodePacked("GEMS_COLLECTION_ENTROPY", block.timestamp));
        createHandshake(collectionEntropyHandshake, MIN_HANDSHAKE_PARTICIPANTS);
    }
    
    modifier inPhase(MintPhase _phase) {
        require(currentPhase == _phase, "Not in the correct phase");
        _;
    }
    
    modifier mintIsOpen {
        require(currentPhase == MintPhase.PREMINT || currentPhase == MintPhase.PUBLIC, "Minting not active");
        require(totalSupply() < MAX_NFT_ITEMS, "Mint has ended");
        _;
    }
    
    /**
     * @dev Transitions to the next mint phase
     */
    function advancePhase() external onlyOwner {
        if (currentPhase == MintPhase.CLOSED) {
            currentPhase = MintPhase.PREMINT;
        } else if (currentPhase == MintPhase.PREMINT) {
            currentPhase = MintPhase.PUBLIC;
        } else if (currentPhase == MintPhase.PUBLIC) {
            require(handshakeComplete[collectionEntropyHandshake], "Collection entropy handshake not complete");
            currentPhase = MintPhase.REVEAL;
            revealActive = true;
            emit RevealActivated();
        }
        
        emit MintPhaseChanged(currentPhase);
    }
    
    /**
     * @dev Public function to participate in the collection entropy handshake
     * @param commitment Hash of a secret value used for the commitment
     */
    function participateInEntropyHandshake(bytes32 commitment) external {
        require(currentPhase != MintPhase.REVEAL, "Reveal already active");
        submitCommitment(collectionEntropyHandshake, commitment);
    }
    
    /**
     * @dev Public function to reveal a secret for the collection entropy handshake
     * @param secret The secret that was hashed for the commitment
     */
    function revealEntropySecret(bytes32 secret) external {
        require(currentPhase != MintPhase.REVEAL, "Reveal already active");
        revealSecret(collectionEntropyHandshake, secret);
    }
    
    /**
     * @dev Main minting function
     * @param to Address to mint the token to
     */
    /**
     * @dev Add or update a fund distribution recipient
     * @param recipient Address to receive funds
     * @param percentage Percentage in basis points (10000 = 100%)
     * @param isFixed Whether this percentage is fixed or random
     */
    function addFundDistribution(address recipient, uint256 percentage, bool isFixed) public onlyOwner {
        require(recipient != address(0), "Invalid recipient address");
        require(percentage <= 10000, "Percentage cannot exceed 100%");
        
        // If fixed, check we don't exceed 50% total fixed allocations
        if (isFixed) {
            // First check if this recipient already exists as fixed
            bool existingRecipient = false;
            uint256 existingPercentage = 0;
            
            for (uint i = 0; i < fundDistributions.length; i++) {
                if (fundDistributions[i].recipient == recipient && fundDistributions[i].isFixed) {
                    existingRecipient = true;
                    existingPercentage = fundDistributions[i].percentage;
                    
                    // Update the entry
                    fundDistributions[i].percentage = percentage;
                    break;
                }
            }
            
            // Calculate new total fixed allocation
            uint256 newTotal;
            if (existingRecipient) {
                newTotal = totalFixedAllocation - existingPercentage + percentage;
            } else {
                newTotal = totalFixedAllocation + percentage;
            }
            
            require(newTotal <= 5000, "Fixed allocations cannot exceed 50%");
            totalFixedAllocation = newTotal;
            
            // Add new distribution if not updating existing
            if (!existingRecipient) {
                fundDistributions.push(FundDistribution(recipient, percentage, isFixed));
            }
        } else {
            // For random distributions, just add or update
            bool existingRecipient = false;
            
            for (uint i = 0; i < fundDistributions.length; i++) {
                if (fundDistributions[i].recipient == recipient && !fundDistributions[i].isFixed) {
                    existingRecipient = true;
                    fundDistributions[i].percentage = percentage;
                    break;
                }
            }
            
            if (!existingRecipient) {
                fundDistributions.push(FundDistribution(recipient, percentage, isFixed));
            }
        }
        
        emit DistributionUpdated(recipient, percentage, isFixed);
    }
    
    /**
     * @dev Commit to a fund distribution by providing a commitment hash
     * @param commitment Hash of your secret for fund distribution (keccak256(secret + address))
     */
    function commitFundDistribution(bytes32 commitment) external payable {
        require(commitment != bytes32(0), "Invalid commitment");
        require(msg.value > 0, "Must send ETH with commitment");
        
        // Create or update the commitment
        FundCommitment storage userCommitment = fundCommitments[msg.sender];
        
        // If updating an existing commitment, add to the amount
        if (userCommitment.commitment != bytes32(0)) {
            userCommitment.amount += msg.value;
        } else {
            // New commitment
            userCommitment.commitment = commitment;
            userCommitment.amount = msg.value;
            userCommitment.timestamp = block.timestamp;
        }
        
        emit FundCommitmentCreated(msg.sender, commitment, msg.value);
    }
    
    /**
     * @dev Reveal a previously committed fund distribution secret
     * @param secret The secret that was hashed for the commitment
     */
    function revealFundSecret(bytes32 secret) external {
        FundCommitment storage userCommitment = fundCommitments[msg.sender];
        require(userCommitment.commitment != bytes32(0), "No commitment found");
        require(!userCommitment.revealed, "Secret already revealed");
        
        // Verify the commitment
        require(keccak256(abi.encodePacked(secret, msg.sender)) == userCommitment.commitment, 
                "Secret does not match commitment");
        
        userCommitment.revealedSecret = secret;
        userCommitment.revealed = true;
        
        emit FundSecretRevealed(msg.sender, secret);
        
        // Distribute funds if there's an amount to distribute
        if (userCommitment.amount > 0) {
            distributeFunds(msg.sender, userCommitment.amount, secret);
        }
    }
    
    /**
     * @dev Distribute funds according to the distribution rules and randomness
     * @param from Address the funds are from
     * @param amount Amount to distribute
     * @param secret Secret used for randomness
     */
    function distributeFunds(address from, uint256 amount, bytes32 secret) internal {
        uint256 remaining = amount;
        
        // First handle fixed distributions
        for (uint i = 0; i < fundDistributions.length; i++) {
            if (fundDistributions[i].isFixed) {
                uint256 allocation = (amount * fundDistributions[i].percentage) / 10000;
                remaining -= allocation;
                
                // Send the fixed allocation
                (bool success, ) = payable(fundDistributions[i].recipient).call{value: allocation}("");
                require(success, "Fixed transfer failed");
            }
        }
        
        // Now handle random distributions
        uint256 totalRandomPercentage = 0;
        uint256[] memory randomRecipientIndexes = new uint256[](fundDistributions.length);
        uint256 randomRecipientCount = 0;
        
        // Collect all random distribution recipients
        for (uint i = 0; i < fundDistributions.length; i++) {
            if (!fundDistributions[i].isFixed) {
                randomRecipientIndexes[randomRecipientCount] = i;
                randomRecipientCount++;
                totalRandomPercentage += fundDistributions[i].percentage;
            }
        }
        
        // If we have random recipients, distribute the remaining funds
        if (randomRecipientCount > 0 && totalRandomPercentage > 0) {
            for (uint i = 0; i < randomRecipientCount; i++) {
                uint256 recipientIndex = randomRecipientIndexes[i];
                
                // Generate semi-random percentage based on the secret and recipient
                uint256 basePercentage = fundDistributions[recipientIndex].percentage;
                
                // Calculate a percentage of the remaining funds
                // This uses both deterministic (basePercentage) and random (secret-based) factors
                uint256 randomFactor = uint256(keccak256(abi.encodePacked(
                    secret, 
                    fundDistributions[recipientIndex].recipient,
                    block.timestamp,
                    i
                ))) % 100;  // 0-99 random factor
                
                // Apply random factor: ±25% of base percentage
                uint256 adjustedPercentage;
                if (randomFactor < 50) {
                    // Reduce by up to 25%
                    uint256 reduction = (basePercentage * (randomFactor * 50 / 100)) / 100;
                    adjustedPercentage = basePercentage - reduction;
                } else {
                    // Increase by up to 25%
                    uint256 increase = (basePercentage * ((randomFactor - 50) * 50 / 100)) / 100;
                    adjustedPercentage = basePercentage + increase;
                }
                
                // Calculate share of remaining funds
                uint256 shareOfRemaining = (remaining * adjustedPercentage) / totalRandomPercentage;
                
                // Don't exceed remaining funds
                if (shareOfRemaining > remaining) {
                    shareOfRemaining = remaining;
                }
                remaining -= shareOfRemaining;
                
                // Send the random allocation
                if (shareOfRemaining > 0) {
                    (bool success, ) = payable(fundDistributions[recipientIndex].recipient).call{value: shareOfRemaining}("");
                    require(success, "Random transfer failed");
                }
            }
        }
        
        // If there's still ETH remaining, send to treasury
        if (remaining > 0) {
            (bool success, ) = payable(treasuryAddress).call{value: remaining}("");
            require(success, "Treasury transfer failed");
        }
        
        emit FundsDistributed(from, amount);
    }
    
    /**
     * @dev Main minting function with fund distribution option
     * @param to Address to mint the token to
     * @param fundCommitmentHash Optional commitment hash for fund distribution
     */
    function safeMint(address to, bytes32 fundCommitmentHash) public mintIsOpen payable {
        require(msg.value >= PRICE, "Insufficient funds");
        
        // Handle fund distribution commitment if provided
        if (fundCommitmentHash != bytes32(0)) {
            // Create commitment with the excess funds (over PRICE)
            uint256 fundAmount = msg.value - PRICE;
            
            if (fundAmount > 0) {
                // Store the commitment
                FundCommitment storage userCommitment = fundCommitments[msg.sender];
                
                // If updating an existing commitment, add to the amount
                if (userCommitment.commitment != bytes32(0)) {
                    userCommitment.amount += fundAmount;
                } else {
                    // New commitment
                    userCommitment.commitment = fundCommitmentHash;
                    userCommitment.amount = fundAmount;
                    userCommitment.timestamp = block.timestamp;
                }
                
                emit FundCommitmentCreated(msg.sender, fundCommitmentHash, fundAmount);
            }
        }
        
        // Mint the token
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }
    
    /**
     * @dev Legacy mint function maintaining backward compatibility
     */
    function safeMint(address to) public mintIsOpen payable {
        safeMint(to, bytes32(0));
    }
    
    /**
     * @dev Generates randomness for a specific token using the collection entropy
     * @param tokenId The token ID to generate randomness for
     */
    function generateTokenRandomness(uint256 tokenId) public inPhase(MintPhase.REVEAL) {
        require(_exists(tokenId), "Token does not exist");
        require(tokenRandomSeeds[tokenId] == bytes32(0), "Randomness already generated");
        
        // Create a unique seed for this token based on the collection entropy
        bytes32 tokenSeed = keccak256(abi.encodePacked(
            getHandshakeEntropy(collectionEntropyHandshake),
            tokenId,
            block.timestamp,
            block.prevrandao
        ));
        
        tokenRandomSeeds[tokenId] = tokenSeed;
        emit TokenRandomnessAssigned(tokenId, tokenSeed);
    }
    
    /**
     * @dev Batch generates randomness for multiple tokens
     * @param tokenIds Array of token IDs to generate randomness for
     */
    function batchGenerateRandomness(uint256[] calldata tokenIds) external inPhase(MintPhase.REVEAL) {
        for (uint i = 0; i < tokenIds.length; i++) {
            if (tokenRandomSeeds[tokenIds[i]] == bytes32(0) && _exists(tokenIds[i])) {
                generateTokenRandomness(tokenIds[i]);
            }
        }
    }
    
    /**
     * @dev Helper function to check if a token exists
     * @param tokenId The token ID to check
     * @return True if the token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    /**
     * @dev Get a random number within a range for a specific token
     * @param tokenId The token ID
     * @param min The minimum value (inclusive)
     * @param max The maximum value (inclusive)
     * @return A random number between min and max
     */
    function getRandomInRange(uint256 tokenId, uint256 min, uint256 max) public view returns (uint256) {
        require(min <= max, "Invalid range");
        require(_exists(tokenId), "Token does not exist");
        require(tokenRandomSeeds[tokenId] != bytes32(0), "Randomness not yet generated");
        
        bytes32 seed = tokenRandomSeeds[tokenId];
        uint256 range = max - min + 1;
        
        return min + (uint256(seed) % range);
    }
    
    // Function to update the renderer (for future upgrades)
    function updateRenderer(address newRendererAddress) external onlyOwner {
        require(newRendererAddress != address(0), "Invalid renderer address");
        renderer = SVGRenderer(newRendererAddress);
    }
    
    // Function to add SVG to a token (convenience method)
    function addSVGToToken(uint256 tokenId, string calldata svgString) external onlyOwner {
        renderer.addSVG(tokenId, svgString);
    }
    
    // Function to batch add SVGs to tokens
    function batchAddSVGs(uint256[] calldata tokenIds, string[] calldata svgStrings) external onlyOwner {
        require(tokenIds.length == svgStrings.length, "Length mismatch");
        for (uint i = 0; i < tokenIds.length; i++) {
            renderer.addSVG(tokenIds[i], svgStrings[i]);
        }
    }
    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
 
        return renderAsDataUri(tokenId);
    }
    
    function renderAsDataUri(uint256 _tokenId) public view returns (string memory) {
        string memory svg;
        string memory attributes;
        (svg, attributes) = renderer.renderSVG(_tokenId);
        
        // Add randomness information to the attributes if available
        if (revealActive && tokenRandomSeeds[_tokenId] != bytes32(0)) {
            string memory randomnessAttribute = string.concat(
                ',"randomSeed":"', 
                Utils.toHexString(uint256(tokenRandomSeeds[_tokenId])),
                '"'
            );
            
            attributes = string.concat(attributes, randomnessAttribute);
        }
        
        string memory image = string.concat('"image":"data:image/svg+xml;base64,', Utils.encode(bytes(svg)),'"');
    
        string memory json = string.concat(
            '{"name":"Gem #',
            Utils.toString(_tokenId),
            '","description":"Gems are virtual crystals with scientifically accurate properties. Each digital gem features authentic mineralogical traits and natural rarity, forever preserved on the blockchain. Stake your Gems in GemFunder DeFi pools or provide liquidity in AMM pools to mine rare crystal rewards, turning your mineralogical collection into a productive asset in our ecosystem.",',
            attributes,
            ',', image,
            '}'
        );
        
        return
            string.concat(
                "data:application/json;base64,",
                Utils.encode(bytes(json))
            );    
    }
    
    /**
     * @dev Hook into token transfers to allow fund distribution with transfer
     * @param fundCommitmentHash Commitment hash for fund distribution during transfer
     */
    function transferWithFunding(uint256 tokenId, address to, bytes32 fundCommitmentHash) external payable {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved or owner");
        
        // Handle fund distribution commitment if provided and ETH sent
        if (fundCommitmentHash != bytes32(0) && msg.value > 0) {
            // Store the commitment
            FundCommitment storage userCommitment = fundCommitments[msg.sender];
            
            // If updating an existing commitment, add to the amount
            if (userCommitment.commitment != bytes32(0)) {
                userCommitment.amount += msg.value;
            } else {
                // New commitment
                userCommitment.commitment = fundCommitmentHash;
                userCommitment.amount = msg.value;
                userCommitment.timestamp = block.timestamp;
            }
            
            emit FundCommitmentCreated(msg.sender, fundCommitmentHash, msg.value);
        }
        
        // Transfer the token
        _transfer(msg.sender, to, tokenId);
    }
    
    /**
     * @dev Check if an address is approved or the owner of a token
     * @param spender Address to check
     * @param tokenId The token to check
     * @return Whether the address is approved or owner
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }
    
    /**
     * @dev Update treasury address (only owner)
     * @param newTreasury New treasury address
     */
    function updateTreasuryAddress(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury address");
        treasuryAddress = newTreasury;
    }
    
    /**
     * @dev Get count of fund distributions
     * @return Count of distribution entries
     */
    function getFundDistributionsCount() external view returns (uint256) {
        return fundDistributions.length;
    }
    
    /**
     * @dev Force distribution for old commitments (emergency function)
     * @param user Address of the user whose funds should be distributed
     * @param defaultSeed Seed to use if the user hasn't revealed
     */
    function forceDistribution(address user, bytes32 defaultSeed) external onlyOwner {
        FundCommitment storage userCommitment = fundCommitments[user];
        require(userCommitment.commitment != bytes32(0), "No commitment found");
        require(userCommitment.amount > 0, "No funds to distribute");
        
        // Only allow force distribution if more than 30 days passed since commitment
        require(block.timestamp > userCommitment.timestamp + 30 days, "Too early to force");
        
        bytes32 seedToUse = userCommitment.revealed ? userCommitment.revealedSecret : defaultSeed;
        uint256 amountToDistribute = userCommitment.amount;
        
        // Reset the commitment amount
        userCommitment.amount = 0;
        
        // Distribute the funds
        distributeFunds(user, amountToDistribute, seedToUse);
    }
    
    // The following functions are overrides required by Solidity.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }
    
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    // Allow withdrawal of ETH
    function withdraw() public onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
    
    // Allow the contract to receive ETH
    receive() external payable {}
}
