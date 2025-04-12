// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { Utils } from './Utils.sol';
import { SVGRenderer } from './SVGRenderer.sol';

contract NFTManager is ERC721, ERC721Enumerable, Ownable {
    uint256 private _nextTokenId;
    
    uint256 public constant PRICE = 0.01 ether;
    uint256 public constant MAX_NFT_ITEMS = 777;
    SVGRenderer public renderer;
    
    // Mapping for random seed storage
    mapping(uint256 => uint256) private tokenRandomSeeds;
    
    // Event for randomness generation
    event RandomnessGenerated(uint256 indexed tokenId, uint256 randomSeed);
    
    constructor(uint256 _reservedForTeam) ERC721("Gems Alpha v1", "GEMS") Ownable(msg.sender) {
        renderer = new SVGRenderer();
        for (uint i=0; i < _reservedForTeam; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
            // Generate randomness for reserved tokens
            generateRandomness(tokenId);
        }
    }
    
    modifier mintIsOpen {
        require(totalSupply() < MAX_NFT_ITEMS, "Mint has ended");
        _;
    }
    
    /**
     * @dev Generates a random seed for a token using blockhash, address, and tokenId
     * @param tokenId The token ID to generate randomness for
     */
    function generateRandomness(uint256 tokenId) internal {
        // Combining multiple entropy sources for better randomness
        uint256 randomSeed = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),  // Previous block hash
                    block.timestamp,              // Current timestamp
                    msg.sender,                   // Sender address
                    tokenId,                      // Token ID
                    address(this),                // Contract address
                    block.difficulty,             // Block difficulty (if available on your chain)
                    gasleft()                     // Remaining gas
                )
            )
        );
        
        // Store the random seed
        tokenRandomSeeds[tokenId] = randomSeed;
        
        // Emit event
        emit RandomnessGenerated(tokenId, randomSeed);
    }
    
    /**
     * @dev Get the random seed for a specific token
     * @param tokenId The token ID
     * @return The random seed
     */
    function getRandomSeed(uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), "Token does not exist");
        return tokenRandomSeeds[tokenId];
    }
    
    /**
     * @dev Generate a random number within a range for a specific token
     * @param tokenId The token ID
     * @param min The minimum value (inclusive)
     * @param max The maximum value (inclusive)
     * @return A random number between min and max
     */
    function getRandomInRange(uint256 tokenId, uint256 min, uint256 max) public view returns (uint256) {
        require(min <= max, "Invalid range");
        require(_exists(tokenId), "Token does not exist");
        
        uint256 seed = tokenRandomSeeds[tokenId];
        uint256 range = max - min + 1;
        
        return min + (seed % range);
    }
    
    /**
     * @dev Helper function to check if a token exists
     * @param tokenId The token ID to check
     * @return True if the token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    function safeMint(address to) public mintIsOpen payable {
        require(msg.value >= PRICE, "Insufficient funds");
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        
        // Generate randomness for the new token
        generateRandomness(tokenId);
    }
    
    // New function to update the renderer (for future upgrades)
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
        
        // Add randomness information to the attributes
        string memory randomnessAttribute = string.concat(
            ',"randomSeed":"', 
            Utils.toString(tokenRandomSeeds[_tokenId]),
            '"'
        );
        
        attributes = string.concat(attributes, randomnessAttribute);
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
